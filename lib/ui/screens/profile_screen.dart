import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../core/dates.dart';
import '../../core/rules.dart';
import '../theme.dart';
import '../widgets.dart';
import 'caregiver_screen.dart';
import 'demo_picker_screen.dart';
import 'doctor_note_screen.dart';
import 'emergency_screen.dart';
import 'library_screen.dart';
import 'lock_screen.dart';
import 'record_proof_screen.dart';
import 'signin_screen.dart';

/// Profile, privacy controls and sync status (MA-03, MA-04, MA-39).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final f = s.facility;
    final consentLabels = {
      'share_with_facility': context.t('Share warning signs with my clinic', 'Shiriki dalili za hatari na kliniki'),
      'share_with_chw': context.t('Community health worker follow-up', 'Ufuatiliaji wa mhudumu wa jamii'),
      'reminders_sms': context.t('SMS reminders', 'Vikumbusho kwa SMS'),
      'reminders_whatsapp': context.t('WhatsApp reminders', 'Vikumbusho kwa WhatsApp'),
      'photo_storage': context.t('Keep baby photos on the server', 'Hifadhi picha za mtoto kwenye seva'),
      'research': context.t('Anonymous research', 'Utafiti bila majina'),
    };
    return Pad(
      children: [
        AppCard(
          child: Row2(
            icon: Icons.person_outline,
            title: s.name.isEmpty ? 'Mama' : s.name,
            sub: s.pregnant
                ? context.t('Pregnant · ${s.weeks} weeks', 'Mjamzito · wiki ${s.weeks}')
                : context.t('${s.babiesLabel} · ${s.babyDays} days', '${s.babiesLabel} · siku ${s.babyDays}'),
            onTap: () => _editName(context),
          ),
        ),
        SectionTitle(context.t('Language', 'Lugha')),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            key: const Key('plang'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'sw',
                label: Text('Kiswahili', key: Key('plang-sw')),
              ),
              ButtonSegment(
                value: 'en',
                label: Text('English', key: Key('plang-en')),
              ),
            ],
            selected: {s.lang},
            onSelectionChanged: (v) => s.setLang(v.first),
          ),
        ),
        SectionTitle(context.t('My clinic', 'Kliniki yangu')),
        AppCard(
          child: Column(
            children: [
              Row2(
                icon: Icons.local_hospital_outlined,
                title: f?['name'] as String? ?? context.t('Not chosen yet', 'Bado haijachaguliwa'),
                sub: f?['phone'] as String?,
                onTap: () => _pickClinic(context),
              ),
              if (s.hasRemote && !s.signedIn) ...[
                const Divider(),
                Row2(
                  icon: Icons.sync,
                  title: context.t('Connect to my clinic', 'Unganisha na kliniki yangu'),
                  sub: context.t(
                    'Sign in with your phone number to back up your records and share them if you choose.',
                    'Ingia kwa namba ya simu kuhifadhi kumbukumbu zako na kuzishiriki ukipenda.',
                  ),
                  onTap: () => go(const SignInScreen()),
                ),
              ],
            ],
          ),
        ),
        SectionTitle(context.t('Care and safety', 'Huduma na usalama')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
          child: Column(
            children: [
              Row2(
                key: const Key('profile-contacts'),
                icon: Icons.contact_phone_outlined,
                tint: C.red,
                title: context.t('Emergency contacts', 'Namba za dharura'),
                sub: context.t('Facility, a person to call, transport', 'Kituo, mtu wa kumpigia, usafiri'),
                onTap: () => go(const EmergencyContactsScreen()),
              ),
              Row2(
                key: const Key('profile-note'),
                icon: Icons.description_outlined,
                title: context.t("Doctor's Note", 'Taarifa kwa daktari'),
                sub: context.t('A summary to show your clinician', 'Muhtasari wa kumwonyesha mhudumu'),
                onTap: () => go(const DoctorNoteScreen()),
              ),
            ],
          ),
        ),
        SectionTitle(context.t('Privacy and sharing', 'Faragha na kushiriki')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final e in consentLabels.entries)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value, style: Theme.of(context).textTheme.titleMedium),
                  value: s.consent(e.key),
                  onChanged: (v) => s.setConsent(e.key, v),
                ),
            ],
          ),
        ),
        if (s.consent('share_with_facility') && f?['id'] == null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              context.t(
                'Sharing starts once you connect and choose your clinic from the list.',
                'Kushiriki kutaanza ukiunganisha na kuchagua kliniki yako kwenye orodha.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const Gap(8),
        AppCard(
          key: const Key('my-helpers'),
          child: Row2(
            icon: Icons.volunteer_activism_outlined,
            title: context.t('My helpers', 'Wasaidizi wangu'),
            sub: context.t('Let a partner or family member follow your checks', 'Mruhusu mwenzi au familia kufuatilia ukaguzi wako'),
            onTap: () => go(const MyHelpersScreen()),
          ),
        ),
        SectionTitle(context.t('This phone', 'Simu hii')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('Lock with a 4-digit PIN', 'Funga kwa PIN ya namba 4')),
                value: s.hasPin,
                onChanged: (v) => v ? go(const _SetPinScreen()) : s.clearPin(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('Read lessons aloud', 'Soma masomo kwa sauti')),
                value: s.readAloud,
                onChanged: (v) => s.setFlag('read_aloud', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('Low data mode', 'Hali ya data kidogo')),
                subtitle: Text(context.t('Sync less often; no media downloads.', 'Sawazisha mara chache; hakuna kupakua media.')),
                value: s.lowData,
                onChanged: (v) => s.setFlag('low_data', v),
              ),
            ],
          ),
        ),
        if (s.signedIn) ...[
          SectionTitle(context.t('Sync', 'Usawazishaji')),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row2(
                  icon: s.pendingCount == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                  title: s.pendingCount == 0
                      ? context.t('Everything is saved', 'Kila kitu kimehifadhiwa')
                      : context.t('${s.pendingCount} waiting to send', '${s.pendingCount} zinasubiri kutumwa'),
                  sub: s.lastSync == null
                      ? null
                      : context.t(
                          'Last sync ${fmtDay(parseTs(s.lastSync!), 'en')} ${fmtTime(parseTs(s.lastSync!))}',
                          'Mara ya mwisho ${fmtDay(parseTs(s.lastSync!), 'sw')} ${fmtTime(parseTs(s.lastSync!))}',
                        ),
                  trailing: s.syncing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                      : IconButton(icon: const Icon(Icons.refresh), onPressed: s.syncNow),
                ),
                if (s.deadCount > 0)
                  Text(
                    context.t(
                      '${s.deadCount} record(s) could not be saved on the server. They are kept on this phone.',
                      'Kumbukumbu ${s.deadCount} hazikuweza kuhifadhiwa kwenye seva. Zimebaki kwenye simu hii.',
                    ),
                    style: const TextStyle(color: C.amber),
                  ),
                if (s.syncError != null && s.syncError != 'waiting to retry')
                  Text(context.t('Will try again when there is a signal.', 'Itajaribu tena kukiwa na mtandao.'), style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
        SectionTitle(context.t('My data', 'Taarifa zangu')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              Row2(icon: Icons.download_outlined, title: context.t('Download my data', 'Pakua taarifa zangu'), onTap: () => _export(context)),
              Row2(
                key: const Key('my-record-proof'),
                icon: Icons.verified_outlined,
                title: context.t('My verifiable record', 'Kumbukumbu yangu inayothibitishwa'),
                sub: context.t('A QR any clinic can check', 'QR ambayo kliniki yoyote inaweza kuhakiki'),
                onTap: () => go(const RecordProofScreen()),
              ),
              Row2(
                icon: Icons.delete_forever_outlined,
                tint: C.red,
                title: context.t('Delete all my data', 'Futa taarifa zangu zote'),
                onTap: () => _delete(context),
              ),
              if (s.signedIn)
                Row2(icon: Icons.logout, title: context.t('Sign out and clear this phone', 'Toka na safisha simu hii'), onTap: () => _signOut(context)),
            ],
          ),
        ),
        if (demoPicker) ...[
          const Gap(12),
          AppCard(
            color: C.amberSoft,
            child: Row2(
              key: const Key('switch-demo'),
              icon: Icons.swap_horiz,
              title: context.t('Preview: switch to another mother', 'Onyesho: badilisha mama'),
              onTap: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await s.deleteAllMyData();
              },
            ),
          ),
        ],
        SectionTitle(context.t('About', 'Kuhusu')),
        AppCard(
          child: Row2(icon: Icons.menu_book_outlined, title: context.t('All lessons', 'Masomo yote'), onTap: () => go(const LibraryScreen())),
        ),
        const Gap(12),
        Text(
          'Safari ya Mama ${AppConfig.appVersion} · ${context.t('rules', 'kanuni')} $rulesVersion · Zatii Technologies · Apache-2.0\n'
          '${s.hasRemote ? '' : context.t('Offline demo: nothing leaves this phone.', 'Onyesho bila mtandao: hakuna kinachotoka kwenye simu hii.')}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Future<void> _editName(BuildContext context) async {
    final s = context.appRead;
    final c = TextEditingController(text: s.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Jina lako' : 'Your name'),
        content: TextField(controller: c, autofocus: true),
        actions: [FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(s.lang == 'sw' ? 'Hifadhi' : 'Save'))],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) await s.setName(c.text);
  }

  Future<void> _pickClinic(BuildContext context) async {
    final s = context.appRead;
    if (s.signedIn) await s.refreshFacilities();
    if (!context.mounted) return;
    final list = s.facilityList;
    final name = TextEditingController(text: s.facility?['name'] as String? ?? ''), phone = TextEditingController(text: s.facility?['phone'] as String? ?? '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (bc) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(bc).viewInsets.bottom),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(s.lang == 'sw' ? 'Chagua kliniki yako' : 'Choose your clinic', style: Theme.of(bc).textTheme.titleLarge),
            for (final f in list)
              ListTile(
                leading: Icon(f['emergency_24h'] == true ? Icons.local_hospital : Icons.medical_services_outlined),
                title: Text(f['name'] as String),
                subtitle: Text('${f['phone'] ?? ''}'),
                onTap: () {
                  s.setFacility({'id': f['id'], 'name': f['name'], 'phone': f['phone']});
                  Navigator.pop(bc);
                },
              ),
            if (list.isEmpty) ...[
              const Gap(8),
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: s.lang == 'sw' ? 'Jina la kliniki' : 'Clinic name'),
              ),
              const Gap(8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.lang == 'sw' ? 'Simu ya kliniki' : 'Clinic phone'),
              ),
              const Gap(12),
              FilledButton(
                onPressed: () {
                  s.setFacility({'id': null, 'name': name.text.trim(), 'phone': phone.text.trim()});
                  Navigator.pop(bc);
                },
                child: Text(s.lang == 'sw' ? 'Hifadhi' : 'Save'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final s = context.appRead;
    final json = s.exportJson();
    await showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Taarifa zako' : 'Your data'),
        content: SizedBox(
          width: 400,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(json, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(dc);
            },
            child: Text(s.lang == 'sw' ? 'Nakili' : 'Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final s = context.appRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Futa taarifa zote?' : 'Delete all your data?'),
        content: Text(
          s.lang == 'sw'
              ? 'Kila kitu kwenye simu hii kitafutwa sasa. Nakala ya seva inafichwa mara moja na kufutwa kabisa baada ya siku 30. Kushiriki kunazimwa.'
              : 'Everything on this phone is deleted now. The server copy is hidden at once and removed for good after 30 days. Sharing is switched off.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(s.lang == 'sw' ? 'Ghairi' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(dc, true),
            child: Text(s.lang == 'sw' ? 'Futa' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await s.deleteAllMyData();
    if (done && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    if (!done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.lang == 'sw'
                ? 'Unahitaji mtandao kufuta nakala ya seva. Jaribu tena ukiwa na mtandao.'
                : 'You need a connection to delete the server copy. Try again when online.',
          ),
        ),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final s = context.appRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Toka?' : 'Sign out?'),
        content: Text(
          s.pendingCount > 0
              ? (s.lang == 'sw'
                    ? 'Kumbukumbu ${s.pendingCount} bado hazijatumwa na zitapotea. Subiri mtandao kwanza.'
                    : '${s.pendingCount} records are not sent yet and will be lost. Wait for a signal first.')
              : (s.lang == 'sw'
                    ? 'Taarifa za simu hii zitafutwa. Zitarudi ukiingia tena.'
                    : 'This phone\'s copy is cleared. It comes back when you sign in again.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(s.lang == 'sw' ? 'Ghairi' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(s.lang == 'sw' ? 'Toka' : 'Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await s.signOut();
  }
}

class _SetPinScreen extends StatefulWidget {
  const _SetPinScreen();
  @override
  State<_SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<_SetPinScreen> {
  String pin = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('Choose a PIN', 'Chagua PIN'))),
    body: Column(
      children: [
        const Gap(24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.all(8),
                width: 18,
                height: 18,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? C.primary : C.surface2),
              ),
          ],
        ),
        const Spacer(),
        PinPad(
          onDigit: (d) async {
            setState(() => pin += d);
            if (pin.length == 4) {
              await context.appRead.setPin(pin);
              if (context.mounted) Navigator.pop(context);
            }
          },
          onBack: () => setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1)),
        ),
        const Gap(24),
      ],
    ),
  );
}
