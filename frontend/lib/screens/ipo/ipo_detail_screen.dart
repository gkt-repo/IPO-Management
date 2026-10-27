import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/ipo_model.dart';
import '../../providers/refresh_job_provider.dart';

class IpoDetailScreen extends ConsumerStatefulWidget {
  final String ipoId;

  const IpoDetailScreen({super.key, required this.ipoId});

  @override
  ConsumerState<IpoDetailScreen> createState() => _IpoDetailScreenState();
}

class _IpoDetailScreenState extends ConsumerState<IpoDetailScreen> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  IpoItemModel? _ipo;
  String? _maskedPan;
  AllotmentStatusEnum _currentStatus = AllotmentStatusEnum.pending;
  int? _allottedQuantity;
  DateTime? _lastCheckedAt;
  String? _diagnosticMessage;
  List<AllotmentHistoryItemModel> _history = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiClient.dio.get('/api/ipo/${widget.ipoId}');
      final ipoData = res.data['ipo'];
      final panData = res.data['userPan'];
      final checkData = res.data['currentCheck'];
      final historyData = res.data['history'] as List? ?? [];

      setState(() {
        _ipo = IpoItemModel.fromJson(ipoData);
        _maskedPan = panData?['masked'] as String?;
        if (checkData != null) {
          _currentStatus = parseAllotmentStatus(checkData['status'] as String?);
          _allottedQuantity = checkData['allottedQuantity'] as int?;
          _lastCheckedAt = checkData['checkedAt'] != null ? DateTime.tryParse(checkData['checkedAt']) : null;
          _diagnosticMessage = checkData['diagnosticMessage'] as String?;
        }
        _history = historyData.map((h) => AllotmentHistoryItemModel.fromJson(h)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load IPO details';
      });
    }
  }

  Future<void> _openOfficialVerificationUrl() async {
    final urlStr = _ipo?.officialVerificationUrl;
    if (urlStr == null || urlStr.isEmpty) return;

    final uri = Uri.parse(urlStr);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlStr')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching link: $e')),
        );
      }
    }
  }

  Widget _buildStatusBanner() {
    Color bg;
    Color fg;
    IconData icon;
    String title;
    String sub;

    switch (_currentStatus) {
      case AllotmentStatusEnum.allotted:
        bg = AppColors.success.withValues(alpha: 0.12);
        fg = AppColors.success;
        icon = Icons.check_circle_rounded;
        title = _allottedQuantity != null && _allottedQuantity! > 0
            ? '$_allottedQuantity Shares Allotted!'
            : 'Allotment Confirmed';
        sub = 'Automated check verified against registrar records.';
        break;
      case AllotmentStatusEnum.notAllotted:
        bg = AppColors.neutral.withValues(alpha: 0.12);
        fg = AppColors.neutral;
        icon = Icons.cancel_rounded;
        title = 'No Shares Allotted';
        sub = 'A conclusive check confirmed zero shares allotted for this application.';
        break;
      case AllotmentStatusEnum.pending:
        bg = AppColors.warning.withValues(alpha: 0.12);
        fg = AppColors.warning;
        icon = Icons.hourglass_top_rounded;
        title = 'Allotment Pending';
        sub = 'Registrar has not yet published final allotment results for this issue.';
        break;
      case AllotmentStatusEnum.lookupFailed:
        bg = AppColors.error.withValues(alpha: 0.12);
        fg = AppColors.error;
        icon = Icons.error_outline_rounded;
        title = 'Automated Lookup Inconclusive';
        sub = _diagnosticMessage ?? 'A technical failure or anti-automation barrier prevented lookup. Never assumed non-allotted.';
        break;
      case AllotmentStatusEnum.notSupported:
        bg = AppColors.info.withValues(alpha: 0.12);
        fg = AppColors.info;
        icon = Icons.info_outline_rounded;
        title = 'Registrar Not Supported';
        sub = 'Automated check is not supported for this registrar. Please verify via official registrar page below.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: fg)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.3)),
                if (_lastCheckedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Checked: ${DateFormat('dd MMM yyyy, hh:mm a').format(_lastCheckedAt!.toLocal())}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_ipo?.name ?? 'IPO Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusBanner(),
                      const SizedBox(height: 20),

                      // Official Registrar Verification Action Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.verified_user_outlined, color: AppColors.accent, size: 24),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Official Registrar Verification',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'PEEK is an automated aggregator, not the final authority. Open the official registrar allotment portal to verify independently with your PAN.',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _openOfficialVerificationUrl,
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(
                                  'Verify on ${_ipo?.registrar ?? "Registrar"} Portal',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Issue Metadata Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Issue Details',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              const Divider(height: 20),
                              _buildDetailRow('Issue Type', _ipo?.issueType ?? 'MAINBOARD'),
                              if (_ipo?.priceBand != null) _buildDetailRow('Price Band', _ipo!.priceBand!),
                              if (_ipo?.lotSize != null) _buildDetailRow('Lot Size', '${_ipo!.lotSize} Shares'),
                              if (_ipo?.openDate != null)
                                _buildDetailRow('Issue Open', DateFormat('dd MMM yyyy').format(_ipo!.openDate!)),
                              if (_ipo?.closeDate != null)
                                _buildDetailRow('Issue Close', DateFormat('dd MMM yyyy').format(_ipo!.closeDate!)),
                              if (_ipo?.allotmentDate != null)
                                _buildDetailRow('Basis of Allotment', DateFormat('dd MMM yyyy').format(_ipo!.allotmentDate!)),
                              if (_ipo?.listingDate != null)
                                _buildDetailRow('Listing Date', DateFormat('dd MMM yyyy').format(_ipo!.listingDate!)),
                              _buildDetailRow('Registrar', _ipo?.registrar ?? 'N/A'),
                              if (_maskedPan != null) _buildDetailRow('Checked With PAN', _maskedPan!),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Allotment History Log Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Allotment Check History',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    onPressed: () {
                                      ref.read(refreshJobProvider.notifier).triggerManualRefresh();
                                      _loadDetails();
                                    },
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              if (_history.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    'No previous check logs for this IPO.',
                                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _history.length,
                                  separatorBuilder: (_, _) => const Divider(height: 16),
                                  itemBuilder: (context, idx) {
                                    final item = _history[idx];
                                    final diag = item.diagnosticMessage != null ? ' • ${item.diagnosticMessage}' : '';
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          margin: const EdgeInsets.only(top: 2),
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: item.status == AllotmentStatusEnum.allotted
                                                ? AppColors.success
                                                : item.status == AllotmentStatusEnum.notAllotted
                                                    ? AppColors.neutral
                                                    : AppColors.error,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    allotmentStatusLabel(item.status),
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                  Text(
                                                    DateFormat('dd MMM, hh:mm a').format(item.timestamp.toLocal()),
                                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Source: ${item.source}$diag',
                                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }
}
