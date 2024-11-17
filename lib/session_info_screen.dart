// lib/session_info_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';



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
  bool hasLeftSession = false;

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
    bool isParticipant = participants.contains(currentUserId);
    hasLeftSession = sessionData!['leftParticipants']?.contains(currentUserId) ?? false;
    isOwner = sessionData!['ownerId'] == currentUserId;

    // Get session title and code
    String sessionTitle = sessionData!['sessionTitle'] ?? 'Session ${widget.sessionCode}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Session Info'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session title
            Text(
              sessionTitle,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            // Session code
            Text(
              'Session Code: ${widget.sessionCode}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            // Created at
            Text(
              'Created At: ${DateFormat.yMMMd().add_jm().format(createdAt)}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            // Participants List
            Text(
              'Participants:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  String participantId = participants[index];
                  String participantName = alternativeNames[participantId] ?? 'Unknown';
                  bool hasLeft = sessionData!['leftParticipants']?.contains(participantId) ?? false;

                  return ListTile(
                    title: Text(
                      participantName,
                      style: TextStyle(
                        decoration: hasLeft ? TextDecoration.lineThrough : null,
                        color: hasLeft ? Colors.grey : Colors.black,
                      ),
                    ),
                    trailing: isOwner && participantId != currentUserId && !hasLeft
                        ? IconButton(
                      icon: Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _confirmKickMember(participantId, participantName),
                    )
                        : null,
                  );
                },
              ),
            ),
            // Leave or Delete Session Button
            if (isParticipant && !hasLeftSession) ...[
              // Show "Leave Session" button
              if (isOwner)
                ElevatedButton(
                  onPressed: _confirmLeaveSession,
                  child: Text('Leave Session (Transfer Ownership)'),
                )
              else
                ElevatedButton(
                  onPressed: _confirmLeaveSession,
                  child: Text('Leave Session'),
                ),
            ] else ...[
              ElevatedButton(
                onPressed: _confirmDeleteSession,
                child: Text('Delete Session'),
              ),
            ],
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
  Future<void> _confirmLeaveSession() async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave Session'),
        content: Text('Are you sure you want to leave this session?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Leave'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      _leaveSession();
    }
  }

  Future<void> _leaveSession() async {
    String userId = _auth.currentUser!.uid;

    if (isOwner) {
      // Transfer ownership
      List<dynamic> participants = List.from(sessionData!['participants']);
      List<dynamic> remainingParticipants = List.from(participants);
      remainingParticipants.remove(userId); // Create a list without the owner for ownership transfer

      if (remainingParticipants.isNotEmpty) {
        // Assign new owner
        String newOwnerId = remainingParticipants.first;
        await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
          'ownerId': newOwnerId,
          'leftParticipants': FieldValue.arrayUnion([userId]),
          // Do not remove the owner from participants
        });
      } else {
        // Delete the session if no participants left
        await _firestore.collection('chat_sessions').doc(widget.sessionCode).delete();
      }
    } else {
      // Regular participant leaving
      await _firestore.collection('chat_sessions').doc(widget.sessionCode).update({
        'leftParticipants': FieldValue.arrayUnion([userId]),
      });
    }

    // Update local state
    setState(() {
      hasLeftSession = true;
      isOwner = false; // The user is no longer the owner
    });

    Navigator.pop(context); // Close SessionInfoScreen
  }



  Future<void> _confirmDeleteSession() async {
    bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Session'),
        content: Text('Are you sure you want to delete this session from your chat list?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      _deleteSession();
    }
  }

  Future<void> _deleteSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> deletedSessions = prefs.getStringList('deletedSessions') ?? [];
    deletedSessions.add(widget.sessionCode);
    await prefs.setStringList('deletedSessions', deletedSessions);

    Navigator.pop(context); // Close SessionInfoScreen
    Navigator.pop(context); // Close ChatScreen
  }

}
