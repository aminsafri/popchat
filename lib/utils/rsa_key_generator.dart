// lib/utils/rsa_key_generator.dart

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart';

Future<Map<String, String>> generateRSAKeyPairIsolate(int keySize) async {
  // Generate RSA key pair
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: keySize);

  final publicKey = keyPair.publicKey as RSAPublicKey;
  final privateKey = keyPair.privateKey as RSAPrivateKey;

  // Encode keys to PEM format
  final publicKeyPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey);
  final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);

  return {
    'publicKeyPem': publicKeyPem,
    'privateKeyPem': privateKeyPem,
  };
}
