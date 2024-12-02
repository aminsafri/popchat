// lib/utils/rsa_key_generator.dart

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asymmetric/api.dart';

Future<Map<String, String>> generateRSAKeyPairIsolate(int keySize) async {
  // Generate RSA key pair
  AsymmetricKeyPair<PublicKey, PrivateKey> keyPair = CryptoUtils.generateRSAKeyPair(keySize: keySize);

  RSAPublicKey publicKey = keyPair.publicKey as RSAPublicKey;
  RSAPrivateKey privateKey = keyPair.privateKey as RSAPrivateKey;

  // Encode keys to PEM format
  String publicKeyPem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(publicKey);
  String privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey);

  // Return keys as a map
  return {
    'publicKeyPem': publicKeyPem,
    'privateKeyPem': privateKeyPem,
  };
}
