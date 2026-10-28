import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pan_provider.dart';
import '../../providers/ipo_provider.dart';
import '../../providers/refresh_job_provider.dart';

class PanSettingsScreen extends ConsumerStatefulWidget {
  const PanSettingsScreen({super.key});

  @override
  ConsumerState<PanSettingsScreen> createState() => _PanSettingsScreenState();
}

class _PanSettingsScreenState extends ConsumerState<PanSettingsScreen> {
  final _panController = TextEditingController();
  bool _consentChecked = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(panProvider.notifier).fetchSavedPan();
    });
  }

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  void _submitSavePan({bool confirmReplace = false}) async {
    if (!confirmReplace && !(_formKey.currentState?.validate() ?? false)) return;

    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check the statutory consent box to store and process your PAN.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final success = await ref.read(panProvider.notifier).savePan(
          pan: _panController.text.trim().toUpperCase(),
          consent: _consentChecked,
          confirmReplace: confirmReplace,
        );

    if (success && mounted) {
      _panController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PAN saved securely with AES-256-GCM encryption.'),
          backgroundColor: AppColors.success,
        ),
      );
      // Trigger refresh for newly saved PAN
      ref.read(refreshJobProvider.notifier).triggerManualRefresh();
      ref.read(ipoListProvider.notifier).fetchIposAndSummary();
    } else if (ref.read(panProvider).replaceRequired && mounted) {
      _showReplaceDialog();
    }
  }

  void _showReplaceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace Saved PAN?'),
        content: const Text(
          'A PAN is already linked to your account. Replacing it will permanently remove previous allotment records and associate all future checks with this new PAN.\n\nDo you wish to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              _submitSavePan(confirmReplace: true);
            },
            child: const Text('Confirm Replace'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Saved PAN?'),
        content: const Text(
          'This will permanently delete your encrypted PAN and all stored allotment history. You will need to link a PAN again to check allotments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await ref.read(panProvider.notifier).deletePan();
              if (success && mounted) {
                ref.read(ipoListProvider.notifier).fetchIposAndSummary();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Saved PAN deleted permanently.'),
                    backgroundColor: AppColors.neutral,
                  ),
                );
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panState = ref.watch(panProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('PAN & Account Settings'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
          ),
        ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Informational Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Strict Single-PAN Security',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Each account supports exactly one PAN. Your PAN is protected with authenticated AES-256-GCM encryption at rest. Decrypted values are never logged or stored in provider databases.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Current Saved PAN Display
            if (panState.hasPan && panState.pan != null) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Saved PAN Card',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle, size: 14, color: AppColors.success),
                                SizedBox(width: 4),
                                Text('ACTIVE', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        panState.pan!.panMasked,
                        style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 3,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Stored securely • Consent granted',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: panState.isLoading ? null : _showDeleteDialog,
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                            label: const Text('Delete PAN', style: TextStyle(color: AppColors.error)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Replace Saved PAN',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter a new 10-character PAN to replace your current saved card.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const Text(
                'Link Your PAN Card',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your 10-character Indian PAN to start automated allotment tracking.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
            ],

            // Input Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _panController,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: 'Permanent Account Number (PAN)',
                      hintText: 'e.g. ABCDE1234F',
                      prefixIcon: const Icon(Icons.credit_card_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.white,
                      counterText: '',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'PAN is required';
                      final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$', caseSensitive: false);
                      if (!regex.hasMatch(val.trim())) {
                        return 'Invalid PAN format. Expected: 5 letters, 4 digits, 1 letter';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Consent Checkbox
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _consentChecked,
                          activeColor: AppColors.accent,
                          onChanged: (val) {
                            setState(() {
                              _consentChecked = val ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _consentChecked = !_consentChecked;
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(top: 8.0, right: 8.0),
                              child: Text(
                                'I explicitly consent to storing my PAN securely to check and display IPO allotment status from official registrars.',
                                style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: panState.isLoading ? null : () => _submitSavePan(confirmReplace: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: panState.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            panState.hasPan ? 'Update & Replace PAN' : 'Save PAN Securely',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Account & Session Section
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account & Session',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    if (ref.watch(authProvider).user?.email != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              ref.watch(authProvider).user!.email,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Sign Out?'),
                              content: const Text('Are you sure you want to sign out of your account?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    await ref.read(authProvider.notifier).logout();
                                    if (context.mounted) context.go('/login');
                                  },
                                  child: const Text('Sign Out'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}
}
