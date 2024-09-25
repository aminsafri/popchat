// lib/home_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_screen.dart';
import 'package:intl/intl.dart'; // For date formatting

class HomeScreen extends StatelessWidget {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  HomeScreen({Key? key}) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    await _auth.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    String userId = _auth.currentUser!.uid;

    // Query to fetch chat sessions where the current user is a participant
    Query chatSessionsQuery = _firestore
        .collection('chat_sessions')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text('Chats'),
        actions: [
          IconButton(icon: Icon(Icons.logout), onPressed: () => _logout(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatSessionsQuery.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          List<DocumentSnapshot> docs = snapshot.data!.docs;

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
              Map<String, dynamic> chatSession = docs[index].data() as Map<String, dynamic>;
              String sessionCode = docs[index].id;
              String lastMessage = chatSession['lastMessage'] ?? '';
              Timestamp? lastMessageTime = chatSession['lastMessageTime'];
              DateTime lastMessageDateTime =
              lastMessageTime != null ? lastMessageTime.toDate() : DateTime.now();

              // Alternative names for participants
              Map<String, dynamic> alternativeNames =
              Map<String, dynamic>.from(chatSession['alternativeNames']);
              String displayName = alternativeNames[userId] ?? 'Unknown';

              // Unread message count (optional)
              Map<String, dynamic> unreadCounts =
              Map<String, dynamic>.from(chatSession['unreadCounts'] ?? {});
              int unreadCount = unreadCounts[userId] ?? 0;

              return Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.blueAccent,
                      child: Text(
                        displayName[0].toUpperCase(),
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                    title: Text(
                      'Session $sessionCode',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(lastMessageDateTime),
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (unreadCount > 0)
                          Container(
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unreadCount',
                              style: TextStyle(color: Colors.white, fontSize: 12),
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
              Navigator.pushNamed(context, '/create_session');
            },
          ),
          ListTile(
            leading: Icon(Icons.group),
            title: Text('Join Chat Session'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/join_session');
            },
          ),
        ],
      ),
    );
  }
}
