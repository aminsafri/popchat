// lib/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String userId = _auth.currentUser!.uid;

    DocumentSnapshot sessionDoc =
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
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

    // Update last message and timestamp in chat session document
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'lastMessage': messageContent,
      'lastMessageTime': Timestamp.now(),
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

    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _kickUser(String userId) async {
    String currentUserId = _auth.currentUser!.uid;

    DocumentSnapshot sessionDoc =
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;

    if (sessionData['ownerId'] != currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only the owner can kick users')),
      );
      return;
    }

    List<dynamic> participants = sessionData['participants'];
    participants.remove(userId);

    Map<String, dynamic> alternativeNames =
    Map<String, dynamic>.from(sessionData['alternativeNames']);
    alternativeNames.remove(userId);

    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'participants': participants,
      'alternativeNames': alternativeNames,
    });
  }

  @override
  Widget build(BuildContext context) {
    String currentUserId = _auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat Session ${widget.sessionCode}'),
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
                      title: Text(
                        message['senderName'],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isMe ? Colors.blue : Colors.black,
                        ),
                      ),
                      subtitle: Text(message['content']),
                      trailing: isMe
                          ? null
                          : IconButton(
                        icon: Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () => _kickUser(message['senderId']),
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
