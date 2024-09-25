// lib/chat_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'session_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final String sessionCode;
  final String alternativeName;

  ChatScreen({required this.sessionCode, required this.alternativeName});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final TextEditingController _messageController = TextEditingController();

  StreamSubscription<DocumentSnapshot>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _listenToSessionChanges();
  }

  void _listenToSessionChanges() {
    _sessionSubscription = _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        // Session no longer exists
        _showSessionEndedDialog();
      } else {
        Map<String, dynamic> sessionData = snapshot.data() as Map<String, dynamic>;
        List<dynamic> participants = sessionData['participants'];
        if (!participants.contains(_auth.currentUser!.uid)) {
          // User is no longer a participant
          _showKickedDialog();
        }
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String userId = _auth.currentUser!.uid;

    DocumentSnapshot sessionDoc =
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    if (!sessionDoc.exists) {
      // Session does not exist
      _showSessionEndedDialog();
      return;
    }

    Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;

    Map<String, dynamic> alternativeNames =
    Map<String, dynamic>.from(sessionData['alternativeNames']);
    String senderName = alternativeNames[userId];

    String messageContent = _messageController.text.trim();

    // Create message document
    await _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .add({
      'senderId': userId,
      'senderName': senderName,
      'timestamp': Timestamp.now(),
      'content': messageContent,
    });

    // Update last message, timestamp, and unread counts
    List<dynamic> participants = sessionData['participants'];

    Map<String, dynamic> unreadCounts = Map<String, dynamic>.from(sessionData['unreadCounts'] ?? {});

    // Increment unread count for other participants
    for (String participantId in participants) {
      if (participantId != userId) {
        unreadCounts[participantId] = (unreadCounts[participantId] ?? 0) + 1;
      }
    }

    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'lastMessage': messageContent,
      'lastMessageTime': Timestamp.now(),
      'unreadCounts': unreadCounts,
    });

    _messageController.clear();
  }

  Stream<QuerySnapshot> _messagesStream() {
    return _firestore
        .collection('chat_sessions')
        .doc(widget.sessionCode)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _leaveSession() async {
    String userId = _auth.currentUser!.uid;

    DocumentSnapshot sessionDoc =
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    if (!sessionDoc.exists) {
      // Session does not exist
      _showSessionEndedDialog();
      return;
    }

    Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;

    List<dynamic> participants = sessionData['participants'];
    participants.remove(userId);

    Map<String, dynamic> alternativeNames =
    Map<String, dynamic>.from(sessionData['alternativeNames']);
    alternativeNames.remove(userId);

    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'participants': participants,
      'alternativeNames': alternativeNames,
    });

    Navigator.pop(context);
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }


  void _showKickedDialog() {
    _sessionSubscription?.cancel();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Removed from Session'),
        content: Text('You have been removed from this session.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to previous screen
            },
          ),
        ],
      ),
    );
  }

  void _showSessionEndedDialog() {
    _sessionSubscription?.cancel();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session Ended'),
        content: Text('This session has ended or been deleted.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to previous screen
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentUserId = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            // Navigate to the session info screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SessionInfoScreen(
                  sessionCode: widget.sessionCode,
                ),
              ),
            );
          },
          child: Text('Session ${widget.sessionCode}'),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.exit_to_app),
            onPressed: _leaveSession,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return CircularProgressIndicator();
                List<DocumentSnapshot> docs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> message =
                    docs[index].data() as Map<String, dynamic>;

                    bool isMe = message['senderId'] == currentUserId;

                    return ListTile(
                      title: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue[200] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            message['content'],
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      subtitle: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          message['senderName'],
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1.0),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration:
                    InputDecoration.collapsed(hintText: 'Send a message'),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
