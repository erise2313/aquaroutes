import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/officer_can.dart';
import '../../utils/error_text.dart';

/// Officers pair a new station with an experienced, accredited one
/// (water_stations.mentor_station_id, patch_stations_members.sql). Both
/// owners are notified and see each other's contact on their dashboard.
/// Only officers can set it; the database refuses an owner.
class MentorStationButton extends StatefulWidget {
  const MentorStationButton({super.key, required this.stationId, required this.stationName});

  final String stationId;
  final String stationName;

  @override
  State<MentorStationButton> createState() => _MentorStationButtonState();
}

class _MentorStationButtonState extends State<MentorStationButton> {
  final _supabase = Supabase.instance.client;
  String? _mentorName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await _supabase
          .from('water_stations')
          .select('mentor_station_id, mentor:water_stations!water_stations_mentor_station_id_fkey(station_name)')
          .eq('id', widget.stationId)
          .single();
      if (mounted) setState(() => _mentorName = row['mentor']?['station_name'] as String?);
    } catch (_) {
      // The button still works; it just doesn't name the current mentor.
    }
  }

  Future<void> _choose() async {
    setState(() => _busy = true);
    List<Map<String, dynamic>> options;
    try {
      options = List<Map<String, dynamic>>.from(await _supabase
          .from('water_stations')
          .select('id, station_name')
          .eq('is_accredited', true)
          .eq('is_active', true)
          .neq('id', widget.stationId)
          .order('station_name'));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    // '' clears the pairing; null is Cancel.
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Mentor for ${widget.stationName}'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Choose an accredited station to help this one through its first months.'),
          ),
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, o['id'] as String),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(o['station_name'] as String? ?? 'Station'),
              ),
            ),
          if (_mentorName != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Remove the mentor')),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _supabase.from('water_stations').update({'mentor_station_id': chosen.isEmpty ? null : chosen}).eq('id', widget.stationId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(chosen.isEmpty ? 'Mentor removed.' : 'Paired. Both stations have been notified.'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OfficerCan(area: OfficerArea.stations, child: TextButton.icon(
      onPressed: _busy ? null : _choose,
      icon: const Icon(Icons.handshake_outlined),
      label: Text(_mentorName == null ? 'Pair with a mentor' : 'Mentor: $_mentorName'),
    ));
  }
}
