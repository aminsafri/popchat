# PopChat

**PopChat** is a secure, feature-rich group chat application built using Flutter and Firebase. It emphasizes privacy and secure communication by leveraging RSA encryption for session keys.

---

## Features

- **User Authentication**: Secure authentication using Firebase Authentication.
- **Session Management**: Join, leave, or create chat sessions with unique codes.
- **Message Encryption**: RSA-based encryption to ensure message privacy.
- **Real-time Messaging**: Send and receive messages in real-time.
- **Secure Group Keys**: Group keys are encrypted and securely distributed to participants.

---

## Technologies Used

- **Flutter**: Cross-platform UI framework.
- **Firebase**: Backend services for authentication, Firestore database, and secure storage.
- **Dart**: Programming language for Flutter.
- **Encrypt Library**: Encryption using RSA and AES.
- **Flutter Secure Storage**: For securely storing sensitive data.

---

## Installation

### Prerequisites

- Flutter installed on your system ([Get Started with Flutter](https://flutter.dev/docs/get-started)).
- Firebase project set up with Firestore and Authentication enabled ([Firebase Console](https://console.firebase.google.com)).

### Steps

1. **Clone the Repository:**

    ```bash
    git clone https://github.com/your-username/popchat.git
    cd popchat
    ```

2. **Install Dependencies:**

    ```bash
    flutter pub get
    ```

3. **Set Up Firebase:**
   - Download the `google-services.json` file from your Firebase Console.
   - Place it in the `android/app` directory.
   - For iOS, download `GoogleService-Info.plist` and place it in the `ios/Runner` directory.

4. **Run the App:**

    ```bash
    flutter run
    ```

---



## Key Functionalities

### **Authentication**
- Email-based user authentication.
- FirebaseAuth integration.

### **Chat Sessions**
- Users can join a session with a unique session code.
- Session-specific encryption keys for secure communication.

### **Message Encryption**
- Messages are encrypted using AES.
- AES keys are securely distributed using RSA encryption.

### **Secure Storage**
- Flutter Secure Storage is used to save private keys and group keys locally.

---

## How It Works

1. **Session Creation**: A new chat session is created, and an RSA-encrypted group key is generated.
2. **Joining a Session**: Users join using a unique code and receive the group key securely.
3. **Real-time Messaging**: Messages are encrypted with AES before being sent to Firestore and decrypted upon receipt.

