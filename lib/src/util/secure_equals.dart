/// Compares two strings in time that depends only on their length, not on
/// where they first differ.
///
/// Use it to compare secrets and signatures, so an attacker cannot guess them
/// byte by byte by measuring response times.
bool secureEquals(String a, String b) {
  if (a.length != b.length) return false;

  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}