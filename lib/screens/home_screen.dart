// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'chat/chat_screen.dart'; // Note the import path
import 'chat/create_session_screen.dart';
import 'chat/join_session_screen.dart';
import 'settings/settings_screen.dart';

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
    // No need to navigate manually; the StreamBuilder in main.dart handles navigation
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('PopChat'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF0088cc), // Telegram-like blue
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _logout(context),
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Retrieve current user's UID
    final userId = _auth.currentUser!.uid;

    // Build query to fetch user's chat sessions
    final chatSessionsQuery = _firestore
        .collection('chat_sessions')
        .where('participants', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true);

    return Scaffold(
      // Modern AppBar with brand color and center title
      appBar: AppBar(
        title: const Text(
          'PopChat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0088cc), // Telegram-like blue
        automaticallyImplyLeading: false, // Remove default back button
        actions: [
          // Settings Icon
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to SettingsScreen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          // Logout Icon
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      // Solid background color to reduce eye strain
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[100], // Light grey background for better contrast
        child: StreamBuilder<QuerySnapshot>(
          stream: chatSessionsQuery.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print('Error fetching chat sessions: ${snapshot.error}');
              return const Center(child: Text('Error loading chat sessions.'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const _NoChatsPlaceholder();
            }

            // Filter out deleted sessions
            final docs = snapshot.data!.docs
                .where((doc) => !deletedSessions.contains(doc.id))
                .toList();

            if (docs.isEmpty) {
              return const _NoChatsPlaceholder();
            }

            return ListView.builder(
              itemCount: docs.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final chatSession =
                docs[index].data()! as Map<String, dynamic>;
                final sessionCode = docs[index].id;

                final lastMessage = chatSession['lastMessage'] ?? '';
                final lastMessageTime =
                chatSession['lastMessageTime'] as Timestamp?;
                final lastMessageDateTime = lastMessageTime != null
                    ? lastMessageTime.toDate()
                    : DateTime.now();

                // Session title
                final sessionTitle =
                    chatSession['sessionTitle'] ?? 'Session $sessionCode';
                // Session image
                final sessionImageUrl =
                    chatSession['sessionImageUrl'] as String? ?? '';
                // Alternative names
                final alternativeNames =
                Map<String, dynamic>.from(chatSession['alternativeNames'] ?? {});
                final displayName =
                    alternativeNames[userId] ??
                        _auth.currentUser?.displayName ??
                        'Unknown';
                // Unread count
                final unreadCounts =
                Map<String, dynamic>.from(chatSession['unreadCounts'] ?? {});
                final unreadCount = unreadCounts[userId] ?? 0;

                // Has user left the session?
                final leftParticipants =
                    chatSession['leftParticipants'] ?? [];
                final hasLeftSession = leftParticipants.contains(userId);

                return _buildChatTile(
                  sessionTitle: sessionTitle,
                  sessionImageUrl: sessionImageUrl,
                  hasLeftSession: hasLeftSession,
                  lastMessage: lastMessage,
                  lastMessageDateTime: lastMessageDateTime,
                  unreadCount: unreadCount,
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
                );
              },
            );
          },
        ),
      ),
      // Floating Action Button for creating/joining sessions
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showChatOptions(context),
        backgroundColor: const Color(0xFF0088cc), // Consistent with AppBar
        elevation: 5,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  /// Builds the bottom sheet for creating or joining a chat session
  void _showChatOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: Colors.white, // White background for clarity
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.add, color: Color(0xFF0088cc)),
            title: const Text(
              'Create Chat Session',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CreateSessionScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.group, color: Color(0xFF0088cc)),
            title: const Text(
              'Join Chat Session',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
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

  /// Builds each chat tile (ListTile) in the list of sessions
  Widget _buildChatTile({
    required String sessionTitle,
    required String sessionImageUrl,
    required bool hasLeftSession,
    required String lastMessage,
    required DateTime lastMessageDateTime,
    required int unreadCount,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _buildSessionAvatar(sessionTitle, sessionImageUrl, hasLeftSession),
          title: Text(
            sessionTitle,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: hasLeftSession ? Colors.grey : Colors.black87,
            ),
          ),
          subtitle: Text(
            lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasLeftSession ? Colors.grey : Colors.black54,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('hh:mm a').format(lastMessageDateTime),
                style: TextStyle(
                  fontSize: 12,
                  color: hasLeftSession ? Colors.grey : Colors.black54,
                ),
              ),
              if (unreadCount > 0 && !hasLeftSession)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent, // More attention-grabbing color
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
          onTap: onTap,
        ),
        // Divider after each session
        const Divider(height: 1, indent: 72, endIndent: 16),
      ],
    );
  }

  /// Builds the session avatar, either using CachedNetworkImage or a fallback
  Widget _buildSessionAvatar(String sessionTitle, String imageUrl, bool hasLeftSession) {
    if (imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => CircleAvatar(
              radius: 24,
              backgroundColor: hasLeftSession ? Colors.grey : const Color(0xFF0088cc),
              child: Text(
                sessionTitle[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
            imageBuilder: (context, imageProvider) => CircleAvatar(
              radius: 24,
              backgroundImage: imageProvider,
            ),
          ),
        ),
      );
    } else {
      return CircleAvatar(
        radius: 24,
        backgroundColor: hasLeftSession ? Colors.grey : const Color(0xFF0088cc),
        child: Text(
          sessionTitle[0].toUpperCase(),
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      );
    }
  }
}

/// A reusable widget when there are no chats to display
class _NoChatsPlaceholder extends StatelessWidget {
  const _NoChatsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No chats yet.\nStart by creating or joining a session.',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey[700], // Darker grey for better readability
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
