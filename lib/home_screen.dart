// lib/home_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';
import 'package:intl/intl.dart';
import 'create_session_screen.dart';
import 'join_session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  List<String> deletedSessions = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeletedSessions();
  }

  Future<void> _loadDeletedSessions() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      deletedSessions = prefs.getStringList('deletedSessions') ?? [];
      isLoading = false;
    });
    print('Deleted sessions: $deletedSessions');
  }

  Future<void> _logout(BuildContext context) async {
    await _auth.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('PopChat'),
          actions: [
            IconButton(
              icon: Icon(Icons.logout),
              onPressed: () => _logout(context),
            ),
          ],
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    String userId = _auth.currentUser!.uid;

    Query chatSessionsQuery = _firestore
        .collection('chat_sessions')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text('PopChat'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatSessionsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            print('Error fetching chat sessions: ${snapshot.error}');
            return Center(child: Text('Error loading chat sessions.'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'No chats yet. Start by creating or joining a session.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            );
          }

          List<DocumentSnapshot> docs = snapshot.data!.docs;

          // Filter out deleted sessions
          docs.removeWhere((doc) => deletedSessions.contains(doc.id));

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No chats yet. Start by creating or joining a session.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              // Extract chat session data
              Map<String, dynamic> chatSession =
              docs[index].data() as Map<String, dynamic>;
              String sessionCode = docs[index].id;
              String lastMessage = chatSession['lastMessage'] ?? '';
              Timestamp? lastMessageTime = chatSession['lastMessageTime'];
              DateTime lastMessageDateTime = lastMessageTime != null
                  ? lastMessageTime.toDate()
                  : DateTime.now();

              // Get session title
              String sessionTitle =
                  chatSession['sessionTitle'] ?? 'Session $sessionCode';

              // Get session image URL
              String sessionImageUrl =
                  chatSession['sessionImageUrl'] as String? ?? '';

              // Alternative names for participants
              Map<String, dynamic> alternativeNames =
              Map<String, dynamic>.from(
                  chatSession['alternativeNames'] ?? {});
              String displayName = alternativeNames[userId] ?? 'Unknown';

              // Unread message count (optional)
              Map<String, dynamic> unreadCounts =
              Map<String, dynamic>.from(chatSession['unreadCounts'] ?? {});
              int unreadCount = unreadCounts[userId] ?? 0;

              // Check if the user has left the session
              List<dynamic> leftParticipants =
                  chatSession['leftParticipants'] ?? [];
              bool hasLeftSession = leftParticipants.contains(userId);

              return Column(
                children: [
                  ListTile(
                    leading: sessionImageUrl.isNotEmpty
                        ? CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.transparent,
                      child: CachedNetworkImage(
                        imageUrl: sessionImageUrl,
                        placeholder: (context, url) =>
                            CircularProgressIndicator(),
                        errorWidget: (context, url, error) =>
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: hasLeftSession
                                  ? Colors.grey
                                  : Colors.blueAccent,
                              child: Text(
                                sessionTitle[0].toUpperCase(),
                                style: TextStyle(
                                    color: Colors.white, fontSize: 20),
                              ),
                            ),
                        imageBuilder: (context, imageProvider) =>
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: imageProvider,
                            ),
                      ),
                    )
                        : CircleAvatar(
                      radius: 24,
                      backgroundColor:
                      hasLeftSession ? Colors.grey : Colors.blueAccent,
                      child: Text(
                        sessionTitle[0].toUpperCase(),
                        style:
                        TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                    title: Text(
                      sessionTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasLeftSession ? Colors.grey : Colors.black,
                      ),
                    ),
                    subtitle: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: hasLeftSession ? Colors.grey : Colors.black),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(lastMessageDateTime),
                          style: TextStyle(
                              fontSize: 12,
                              color:
                              hasLeftSession ? Colors.grey : Colors.black),
                        ),
                        if (unreadCount > 0 && !hasLeftSession)
                          Container(
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unreadCount',
                              style:
                              TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            sessionCode: sessionCode,
                            alternativeName: displayName,
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 72),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.chat),
        onPressed: () {
          _showChatOptions(context);
        },
      ),
    );
  }

  void _showChatOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.add),
            title: Text('Create Chat Session'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateSessionScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.group),
            title: Text('Join Chat Session'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => JoinSessionScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
