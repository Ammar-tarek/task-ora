// test/task_handoff_lock_test.dart
// Phase D — handoff DIRECT-TRANSFER decision logic (UI mirror of the DB guards).
// Real enforcement is the DB triggers/RPC/policy in PROPOSED_handoff_rpcs.sql +
// PROPOSED_task_handoff_field_lock.sql (require the migrations applied; cannot be
// exercised locally). These tests pin the client-side decisions that keep the UI
// in step with the DB in the direct-transfer model (no accept/reject state).

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_model.dart';
import 'package:task_ora/core/utils/task_handoff_lock.dart';

const _src = 'team-src';
const _dst = 'team-dst';

// A normal task owned by its team; a transferred task now owned by the receiver
// (teamId == dst) and stamped with the sender (handoffFromTeamId == src).
TaskModel _task({String? teamId = _src, String? from}) => TaskModel(
      id: 't1',
      title: 'Task',
      createdBy: 'u1',
      status: 'in_progress',
      priority: 'medium',
      completionPercentage: 0,
      createdAt: '2026-10-01',
      teamId: teamId,
      handoffFromTeamId: from,
    );

void main() {
  final normal = _task(); // never handed off, owned by src
  final transferred = _task(teamId: _dst, from: _src); // now owned by dst

  group('state detection', () {
    test('normal task is not transferred/locked', () {
      expect(TaskHandoffLock.isTransferred(normal), isFalse);
      expect(TaskHandoffLock.isLocked(normal), isFalse);
    });
    test('transferred task is detected', () {
      expect(TaskHandoffLock.isTransferred(transferred), isTrue);
      expect(TaskHandoffLock.isLocked(transferred), isTrue);
    });
  });

  group('canEditDefinition', () {
    test('normal task: editable (role perms apply on top)', () {
      expect(TaskHandoffLock.canEditDefinition(normal, isGlobalAdmin: false), isTrue);
    });
    test('transferred task: locked for a non-admin (incl. receiving manager)', () {
      expect(TaskHandoffLock.canEditDefinition(transferred, isGlobalAdmin: false), isFalse);
    });
    test('global admin overrides the lock', () {
      expect(TaskHandoffLock.canEditDefinition(transferred, isGlobalAdmin: true), isTrue);
    });
  });

  group('canTrackStatus (receiving-only)', () {
    test('receiving team can track', () {
      expect(TaskHandoffLock.canTrackStatus(transferred, myTeamId: _dst), isTrue);
    });
    test('sending team cannot track (view only)', () {
      expect(TaskHandoffLock.canTrackStatus(transferred, myTeamId: _src), isFalse);
    });
    test('global admin can track', () {
      expect(
          TaskHandoffLock.canTrackStatus(transferred, myTeamId: _src, isGlobalAdmin: true),
          isTrue);
    });
    test('normal task: trackable (role perms apply on top)', () {
      expect(TaskHandoffLock.canTrackStatus(normal, myTeamId: _src), isTrue);
    });
  });

  group('canAssign', () {
    test('receiving manager can assign', () {
      expect(
          TaskHandoffLock.canAssign(transferred,
              isManager: true, myTeamId: _dst, isGlobalAdmin: false),
          isTrue);
    });
    test('sending manager cannot assign', () {
      expect(
          TaskHandoffLock.canAssign(transferred,
              isManager: true, myTeamId: _src, isGlobalAdmin: false),
          isFalse);
    });
    test('receiving employee cannot assign', () {
      expect(
          TaskHandoffLock.canAssign(transferred,
              isManager: false, myTeamId: _dst, isGlobalAdmin: false),
          isFalse);
    });
    test('global admin can assign', () {
      expect(
          TaskHandoffLock.canAssign(transferred,
              isManager: false, myTeamId: _src, isGlobalAdmin: true),
          isTrue);
    });
  });

  group('delete + re-transfer locks', () {
    test('transferred task cannot be deleted by a department', () {
      expect(TaskHandoffLock.canDelete(transferred, isGlobalAdmin: false), isFalse);
      expect(TaskHandoffLock.canDelete(transferred, isGlobalAdmin: true), isTrue);
    });
    test('transferred task cannot be re-handed-off by a department', () {
      expect(TaskHandoffLock.canHandoff(transferred, isGlobalAdmin: false), isFalse);
      expect(TaskHandoffLock.canHandoff(transferred, isGlobalAdmin: true), isTrue);
    });
    test('normal task can be deleted / handed off (subject to role perms)', () {
      expect(TaskHandoffLock.canDelete(normal, isGlobalAdmin: false), isTrue);
      expect(TaskHandoffLock.canHandoff(normal, isGlobalAdmin: false), isTrue);
    });
  });
}
