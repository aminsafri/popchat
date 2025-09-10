# PopChat 🔐💬

A secure, end-to-end encrypted group chat application built with Flutter and Firebase, emphasizing privacy and identity verification.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

## Features

### Security & Privacy
- **End-to-End Encryption**: Messages encrypted with AES-256, keys secured with RSA-2048
- **Session-Based Security**: Unique encryption keys for each chat session
- **Forward Secrecy**: New group keys generated when participants join/leave
- **Local Key Storage**: Private keys stored securely on device using Flutter Secure Storage

### Identity Verification
- **Passport Verification**: OCR-based identity verification using Google ML Kit
- **MRZ Processing**: Automatic extraction of name data from passport Machine Readable Zone
- **Verified Identity Sharing**: Option to share verified real name in conversations

### Chat Features
- **Real-Time Messaging**: Instant message delivery with Firebase Firestore
- **Session Management**: Create/join sessions with unique codes and optional secret keys
- **Participant Controls**: Session owners can manage participants and transfer ownership
- **Unread Tracking**: Smart notification system with unread message counts
- **Message History**: Persistent encrypted message storage

### User Experience
- **Cross-Platform**: Native performance on Android
- **Alternative Names**: Use pseudonyms in different chat sessions
- **Session Images**: Custom images for chat sessions

## Architecture

### Security Model
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   RSA KeyPair   │    │   AES Group Key  │    │   Encrypted     │
│  (Per User)     │───▶│  (Per Session)   │───▶│   Messages      │
│                 │    │                  │    │                 │
│ Private: Local  │    │ Encrypted with   │    │ Stored in       │
│ Public: Cloud   │    │ Each User's RSA  │    │ Firestore       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Tech Stack
- **Frontend**: Flutter (Dart)
- **Backend**: Firebase (Firestore, Auth, Storage)
- **Encryption**: RSA-2048 + AES-256-CBC
- **OCR**: Google ML Kit Text Recognition
- **Storage**: Flutter Secure Storage
- **Authentication**: Firebase Phone Auth

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/popchat.git
   cd popchat
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Firebase Setup**
   
   Create a new Firebase project at [Firebase Console](https://console.firebase.google.com)
   
   **For Android:**
   - Add Android app to your Firebase project
   - Download `google-services.json`
   - Place it in `android/app/`
   

4. **Configure Firebase Services**
   - Enable **Authentication** (Phone provider)
   - Enable **Firestore Database**
   - Enable **Storage**
   - Optional: Enable **App Check** for additional security

5. **Update Firebase Configuration**
   ```bash
   # Install Firebase CLI
   npm install -g firebase-tools
   
   # Login and configure
   firebase login
   flutterfire configure
   ```

6. **Run the app**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── screens/
│   ├── login_screen.dart             # Phone authentication
│   ├── verification_screen.dart      # OTP verification
│   ├── additional_info_screen.dart   # User setup & key generation
│   ├── home_screen.dart             # Chat sessions list
│   ├── chat/
│   │   ├── chat_screen.dart         # Main chat interface
│   │   ├── create_session_screen.dart # Session creation
│   │   ├── join_session_screen.dart   # Session joining
│   │   └── session_info_screen.dart   # Session management
│   └── settings/
│       ├── settings_screen.dart      # App settings
│       └── passport_verification_screen.dart # Identity verification
└── utils/
    └── rsa_key_generator.dart        # Cryptographic utilities
```

## 🔐 Security Implementation

### Key Generation & Distribution
1. **User Registration**: RSA-2048 key pair generated locally
2. **Key Storage**: Private key in secure storage, public key in Firestore
3. **Session Creation**: AES-256 group key generated and encrypted for each participant
4. **Key Rotation**: New group keys when membership changes

### Message Encryption Flow
```dart
// Encryption
AES-256-CBC(message, groupKey) + IV → Encrypted Message → Firestore

// Decryption  
Firestore → Encrypted Message → AES-256-CBC-Decrypt(encMessage, groupKey) → Plain Text
```

## 🆔 Passport Verification

The app includes an innovative identity verification system:

1. **Image Capture**: Camera or gallery image of passport
2. **OCR Processing**: ML Kit extracts text from passport MRZ
3. **Data Parsing**: Automatic extraction of name and nationality
4. **Verification Storage**: Verified status and name stored in Firestore
5. **Identity Sharing**: Option to share verified real name in chats
