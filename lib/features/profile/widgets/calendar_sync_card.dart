import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';

/// Profil: LifeHub mit dem Kalender des Handys verbinden – Handy-Termine anzeigen (Kalender wählbar)
/// und LifeHub-Termine in einen eigenen Handy-Kalender „LifeHub“ schreiben.
class CalendarSyncCard extends StatefulWidget {
  final int userid;
  const CalendarSyncCard({super.key, required this.userid});

  @override
  State<CalendarSyncCard> createState() => _CalendarSyncCardState();
}

class _CalendarSyncCardState extends State<CalendarSyncCard> {
  late final CalendarSync _sync = context.read<CalendarSync>();
  CalendarSyncSettings? _settings;
  List<DeviceCalendar> _calendars = const [];
  bool _busy = false;

  int get _uid => widget.userid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _sync.settings(_uid);
    final calendars = settings.read ? await _sync.selectableCalendars(_uid) : const <DeviceCalendar>[];
    if (mounted) {
      setState(() {
        _settings = settings;
        _calendars = calendars;
      });
    }
  }

  void _noAccess() => showAppSnack(
        context,
        'Ohne Zugriff auf den Kalender geht das nicht – erlaube ihn in den Android-Einstellungen unter Apps › LifeHub › Berechtigungen.',
        error: true,
      );

  Future<void> _toggleRead(bool on) async {
    setState(() => _busy = true);
    if (on) {
      if (!await _sync.device.requestAccess()) {
        if (mounted) setState(() => _busy = false);
        _noAccess();
        return;
      }
      // Beim ersten Einschalten alle sichtbaren Kalender anzeigen
      final calendars = await _sync.selectableCalendars(_uid);
      final chosen = _settings!.calendarIds.isEmpty ? {for (final c in calendars) c.id} : _settings!.calendarIds;
      await _sync.saveRead(_uid, read: true, calendarIds: chosen);
    } else {
      await _sync.saveRead(_uid, read: false, calendarIds: _settings!.calendarIds);
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleCalendar(String id, bool on) async {
    final ids = {..._settings!.calendarIds};
    on ? ids.add(id) : ids.remove(id);
    await _sync.saveRead(_uid, read: true, calendarIds: ids);
    await _load();
  }

  Future<void> _toggleWrite(bool on) async {
    final repo = context.read<AppointmentRepository>();
    setState(() => _busy = true);
    if (on) {
      final id = await runGuarded(context, () => _sync.enableWrite(_uid));
      if (id == null) {
        if (mounted) setState(() => _busy = false);
        _noAccess();
        return;
      }
      final n = await repo.mirrorAll(_uid);
      if (mounted) showAppSnack(context, '$n ${n == 1 ? 'Termin' : 'Termine'} im Handy-Kalender „${CalendarSync.calendarName}“');
    } else {
      await _sync.disableWrite(_uid);
      await repo.forgetDeviceLinks(_uid);
      if (mounted) showAppSnack(context, 'Kalender „${CalendarSync.calendarName}“ vom Handy entfernt');
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    final s = _settings;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.event_available_rounded, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(child: Text('Handy-Kalender', style: t.titleSmall)),
        ]),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            'Alles, was am Handy im Kalender steht (Google, Samsung …), erscheint in LifeHub. Das läuft nur auf dem Handy, '
            'ohne Internet und ohne Anmeldung.',
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
        ),
        if (s == null)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Handy-Termine anzeigen'),
            subtitle: const Text('Im Kalender und unter „Als Nächstes“ auf Heute'),
            value: s.read,
            onChanged: _busy ? null : _toggleRead,
          ),
          if (s.read)
            for (final cal in _calendars)
              CheckboxListTile(
                contentPadding: const EdgeInsets.only(left: 8),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                secondary: CircleAvatar(radius: 6, backgroundColor: Color(cal.color | 0xFF000000)),
                title: Text(cal.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                value: s.calendarIds.contains(cal.id),
                onChanged: _busy ? null : (v) => _toggleCalendar(cal.id, v ?? false),
              ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LifeHub-Termine ins Handy schreiben'),
            subtitle: Text('In einen eigenen Kalender „${CalendarSync.calendarName}“ – deine anderen Kalender bleiben unberührt. '
                'Erinnerungen kommen weiter von LifeHub.'),
            value: s.write,
            onChanged: _busy ? null : _toggleWrite,
          ),
        ],
      ]),
    );
  }
}
