import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/user_requests_repository.dart';

void main() {
  test('only pending requests can be cancelled by the parishioner', () {
    expect(UserRequestsRepository.canCancel('pending'), isTrue);
    expect(UserRequestsRepository.canCancel(' Pending '), isTrue);
    for (final s in ['rejected', 'approved', 'ready', 'completed', 'cancelled']) {
      expect(UserRequestsRepository.canCancel(s), isFalse, reason: s);
    }
  });
}
