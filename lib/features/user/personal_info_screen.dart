import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import '../../state/auth_controller.dart';
import '../auth/widgets/auth_backdrop.dart';
import 'widgets/profile_widgets.dart';

/// Edit name and phone. Email is shown but not editable: changing it goes
/// through Supabase's confirm-both-addresses flow, which is not built yet.
class PersonalInfoScreen extends ConsumerStatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  ConsumerState<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<PersonalInfoScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _name.text = user?.name ?? '';
    _phone.text = user?.phone ?? '';
    _email.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(name: _name.text, phone: _phone.text);
      _toast('Your details have been saved.');
    } on ApiException catch (e) {
      _toast(e.message);
    } on Exception {
      _toast('Could not save your details. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => ProfileSubpage(
    title: 'Personal Information',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        AuthField(
          label: 'Full name',
          hint: 'Your name',
          icon: Icons.person_outline,
          controller: _name,
          enabled: !_saving,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Phone number',
          hint: '0712 345 678',
          icon: Icons.phone_outlined,
          controller: _phone,
          keyboardType: TextInputType.phone,
          enabled: !_saving,
          helperText: 'Pre-filled when you pay with M-Pesa',
          textInputAction: TextInputAction.done,
          onSubmitted: _save,
        ),
        const SizedBox(height: 16),
        AuthField(
          label: 'Email address',
          hint: '',
          icon: Icons.mail_outline,
          controller: _email,
          enabled: false,
          helperText: "Email can't be changed in the app yet",
        ),
        const SizedBox(height: 28),
        ProfilePrimaryButton(
          label: 'Save changes',
          onPressed: _save,
          busy: _saving,
        ),
      ],
    ),
  );
}
