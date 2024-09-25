// lib/session_info_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';


class SessionInfoScreen extends StatefulWidget {
  final String sessionCode;

  SessionInfoScreen({required this.sessionCode});

  @override
  _SessionInfoScreenState createState() => _SessionInfoScreenState();
}

class _SessionInfoScreenState extends State<SessionInfoScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? sessionData;
  bool isLoading = true;
  bool isOwner = false;
  String currentUserId = '';

  @override
  void initState() {
    super.initState();
    currentUserId = _auth.currentUser!.uid;
    _fetchSessionData();
  }

  Future<void> _fetchSessionData() async {
    DocumentSnapshot doc = await _firestore.collection('chat_sessions').doc(widget.sessionCode).get();
    if (doc.exists) {
      setState(() {
        sessionData = doc.data() as Map<String, dynamic>;
        isOwner = sessionData!['ownerId'] == currentUserId;
        isLoading = false;
      });
    } else {
      // Handle session not found
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session not found')),
      );
    }
  }

  Future<void> _kickMember(String userId) async {
    if (!isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only the owner can kick members')),
      );
      return;
    }

    // Remove user from participants
    List<dynamic> participants = List.from(sessionData!['participants']);
    participants.remove(userId);

    // Remove user from alternativeNames
    Map<String, dynamic> alternativeNames = Map.from(sessionData!['alternativeNames']);
    alternativeNames.remove(userId);

    // Update Firestore
    await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
      'participants': participants,
      'alternativeNames': alternativeNames,
    });

    // Update local state
    setState(() {
      sessionData!['participants'] = participants;
      sessionData!['alternativeNames'] = alternativeNames;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Member kicked')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Session Info'),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (sessionData == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Session Info'),
        ),
        body: Center(child: Text('Session not found')),
      );
    }

    List<dynamic> participants = sessionData!['participants'];
    Map<String, dynamic> alternativeNames = sessionData!['alternativeNames'];
    Timestamp createdAtTimestamp = sessionData!['createdAt'];
    DateTime createdAt = createdAtTimestamp.toDate();

    return Scaffold(
      appBar: AppBar(
        title: Text('Session Info'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Code: ${widget.sessionCode}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('Created At: ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt)}', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            Text('Participants:', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  String userId = participants[index];
                  String displayName = alternativeNames[userId] ?? 'Unknown';

                  return ListTile(
                    title: Text(displayName),
                    subtitle: Text(userId),
                    trailing: isOwner && userId != currentUserId
                        ? IconButton(
                      icon: Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _confirmKickMember(userId, displayName),
                    )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmKickMember(String userId, String displayName) async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kick Member'),
        content: Text('Are you sure you want to kick $displayName?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Kick'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      _kickMember(userId);
    }
  }
}
