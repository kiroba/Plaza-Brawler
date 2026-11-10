// Identity transfer codes: the same person's Ed25519 seed, carried between
// Omni apps on one phone. Android sandboxes each app's storage, so the seed
// cannot be shared in place - LPE (the identity home) exports a code and
// this app imports it into its own secure store.
//
// Format: `omni-seed-v1.<base64 seed>.<check>`, <check> = first 8 hex chars
// of sha256(seed). Mirrors kiroba/LPE lib/lpe_identity.dart - keep the two
// implementations in lockstep. THE CODE IS THE IDENTITY: anyone holding it
// can sign as the person.
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Parses a transfer code. Returns the 32-byte seed, or null for anything
/// malformed - wrong prefix, bad base64, wrong length, checksum mismatch.
List<int>? seedFromIdentityTransferCode(String code) {
  final parts = code.trim().split('.');
  if (parts.length != 3 || parts[0] != 'omni-seed-v1') return null;
  try {
    final seed = base64Decode(parts[1]);
    if (seed.length != 32) return null;
    if (sha256.convert(seed).toString().substring(0, 8) != parts[2]) {
      return null;
    }
    return seed;
  } catch (_) {
    return null;
  }
}
