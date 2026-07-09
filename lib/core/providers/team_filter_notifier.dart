// lib/core/providers/team_filter_notifier.dart
// Global team filter for admin's "view by team" switcher.
// Manager always sees their own team — this is admin-only state.

import 'package:flutter/foundation.dart';
import '../models/team_model.dart';
import '../repositories/team_repository.dart';

class TeamFilterNotifier extends ChangeNotifier {
  String? _selectedTeamId;
  List<TeamModel> _teams = [];
  bool _loaded = false;

  String? get selectedTeamId => _selectedTeamId;
  List<TeamModel> get teams => _teams;
  TeamModel? get selectedTeam => _selectedTeamId == null
      ? null
      : _teams.cast<TeamModel?>().firstWhere(
          (t) => t?.id == _selectedTeamId,
          orElse: () => null,
        );

  Future<void> loadTeams() async {
    if (_loaded) return;
    _teams = await TeamRepository.fetchAll(activeOnly: true);
    _loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    _loaded = false;
    _teams = await TeamRepository.fetchAll(activeOnly: true);
    _loaded = true;
    notifyListeners();
  }

  void select(String? teamId) {
    if (_selectedTeamId == teamId) return;
    _selectedTeamId = teamId;
    notifyListeners();
  }

  void clear() => select(null);
}
