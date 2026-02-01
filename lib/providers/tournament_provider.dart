import 'package:flutter/foundation.dart';
import '../models/tournament.dart';
import '../services/tournament_service.dart';
import '../services/socket_service.dart';

class TournamentProvider extends ChangeNotifier {
  List<Tournament> _allTournaments = [];
  List<Tournament> _upcomingTournaments = [];
  List<Tournament> _registeredTournaments = [];
  List<Tournament> _activeTournaments = [];
  List<TournamentMatch> _pendingMatches = [];
  TournamentMatch? _activeMatch;
  Tournament? _currentTournament;
  List<TournamentMatch> _currentBracket = [];
  bool _isLoading = false;
  String? _error;

  List<Tournament> get allTournaments => _allTournaments;
  List<Tournament> get upcomingTournaments => _upcomingTournaments;
  List<Tournament> get registeredTournaments => _registeredTournaments;
  List<Tournament> get activeTournaments => _activeTournaments;
  List<TournamentMatch> get pendingMatches => _pendingMatches;
  TournamentMatch? get activeMatch => _activeMatch;
  Tournament? get currentTournament => _currentTournament;
  List<TournamentMatch> get currentBracket => _currentBracket;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasPendingInvite => _pendingMatches.isNotEmpty;

  Future<void> loadAllTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allTournaments = await TournamentService.getAllTournaments();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading all tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUpcomingTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _upcomingTournaments = await TournamentService.getUpcomingTournaments();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading upcoming tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMyTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await TournamentService.getMyTournaments();
      _registeredTournaments = result['registered'] ?? [];
      _activeTournaments = result['active'] ?? [];
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading my tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTournament(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentTournament = await TournamentService.getTournament(id);
      _currentBracket = await TournamentService.getBracket(id);
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading tournament: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBracket(String tournamentId) async {
    try {
      _currentBracket = await TournamentService.getBracket(tournamentId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading bracket: $e');
    }
  }

  Future<void> loadPendingMatches() async {
    try {
      _pendingMatches = await TournamentService.getPendingMatches();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading pending matches: $e');
    }
  }

  Future<void> loadActiveMatch() async {
    try {
      _activeMatch = await TournamentService.getActiveMatch();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading active match: $e');
    }
  }

  Future<bool> registerForTournament(String tournamentId) async {
    try {
      await TournamentService.registerForTournament(tournamentId);
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> unregisterFromTournament(String tournamentId) async {
    try {
      await TournamentService.unregisterFromTournament(tournamentId);
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> setMatchReady(String matchId) async {
    try {
      await TournamentService.setMatchReady(matchId);
      await loadPendingMatches();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> isRegisteredForTournament(String tournamentId) async {
    try {
      final result = await TournamentService.getMyRegistration(tournamentId);
      return result['registered'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  void setupSocketListeners() {
    try {
      SocketService.on('tournamentRegistrationOpen', (data) {
        debugPrint('Tournament registration open: $data');
        loadUpcomingTournaments();
      });

      SocketService.on('tournamentMatchInvite', (data) {
        debugPrint('Tournament match invite: $data');
        loadPendingMatches();
      });

      SocketService.on('tournamentMatchStart', (data) {
        debugPrint('Tournament match start: $data');
        loadActiveMatch();
        loadPendingMatches();
      });

      SocketService.on('tournamentMatchResult', (data) {
        debugPrint('Tournament match result: $data');
        loadMyTournaments();
        loadActiveMatch();
      });

      SocketService.on('tournamentNextMatch', (data) {
        debugPrint('Tournament next match: $data');
        loadPendingMatches();
      });

      SocketService.on('tournamentEliminated', (data) {
        debugPrint('Tournament eliminated: $data');
        loadMyTournaments();
      });

      SocketService.on('tournamentComplete', (data) {
        debugPrint('Tournament complete: $data');
        loadMyTournaments();
        loadAllTournaments();
      });

      SocketService.on('matchReadyUpdate', (data) {
        debugPrint('Match ready update: $data');
        loadPendingMatches();
      });
    } catch (e) {
      debugPrint('Error setting up tournament socket listeners: $e');
    }
  }

  void clearSocketListeners() {
    try {
      SocketService.off('tournamentRegistrationOpen');
      SocketService.off('tournamentMatchInvite');
      SocketService.off('tournamentMatchStart');
      SocketService.off('tournamentMatchResult');
      SocketService.off('tournamentNextMatch');
      SocketService.off('tournamentEliminated');
      SocketService.off('tournamentComplete');
      SocketService.off('matchReadyUpdate');
    } catch (e) {
      debugPrint('Error clearing tournament socket listeners: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearCurrentTournament() {
    _currentTournament = null;
    _currentBracket = [];
    notifyListeners();
  }
}
