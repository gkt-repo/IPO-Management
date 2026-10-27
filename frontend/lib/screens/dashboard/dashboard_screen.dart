import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/ipo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pan_provider.dart';
import '../../providers/ipo_provider.dart';
import '../../providers/refresh_job_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1. Fetch cached IPO data and previously stored allotment results immediately
      ref.read(panProvider.notifier).fetchSavedPan();
      ref.read(ipoListProvider.notifier).fetchIposAndSummary();

      // 2. Start asynchronous app-open refresh without blocking UI
      ref.read(refreshJobProvider.notifier).triggerAppOpenRefresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSummaryCard(String title, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(AllotmentStatusEnum status, int? shares) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AllotmentStatusEnum.allotted:
        bg = AppColors.success.withValues(alpha: 0.12);
        fg = AppColors.success;
        label = shares != null && shares > 0 ? '$shares SHARES ALLOTTED' : 'ALLOTTED';
        break;
      case AllotmentStatusEnum.notAllotted:
        bg = AppColors.neutral.withValues(alpha: 0.12);
        fg = AppColors.neutral;
        label = 'NOT ALLOTTED';
        break;
      case AllotmentStatusEnum.pending:
        bg = AppColors.warning.withValues(alpha: 0.12);
        fg = AppColors.warning;
        label = 'PENDING';
        break;
      case AllotmentStatusEnum.lookupFailed:
        bg = AppColors.error.withValues(alpha: 0.12);
        fg = AppColors.error;
        label = 'LOOKUP FAILED';
        break;
      case AllotmentStatusEnum.notSupported:
        bg = AppColors.info.withValues(alpha: 0.12);
        fg = AppColors.info;
        label = 'NOT SUPPORTED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ipoState = ref.watch(ipoListProvider);
    final refreshState = ref.watch(refreshJobProvider);
    final panState = ref.watch(panProvider);

    final summary = ipoState.summary;
    final filteredList = ipoState.filteredIpos;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('IPO Allotment Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.credit_card),
            tooltip: 'PAN Settings',
            onPressed: () => context.go('/pan-settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: refreshState.isRefreshing
            ? null
            : () => ref.read(refreshJobProvider.notifier).triggerManualRefresh(),
        icon: refreshState.isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.refresh),
        label: Text(refreshState.isRefreshing ? 'Scanning...' : 'Refresh Allotments'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(ipoListProvider.notifier).fetchIposAndSummary();
          await ref.read(refreshJobProvider.notifier).triggerManualRefresh();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // No PAN linked banner
              if (!panState.hasPan && !panState.isLoading) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'No PAN Card Linked',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Link your PAN to enable automatic allotment verification.',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => context.go('/pan-settings'),
                        child: const Text('Link PAN', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],

              // Refresh Banner & Progress Bar
              if (refreshState.isRefreshing) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              refreshState.statusMessage ?? 'Refreshing allotment data...',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ),
                      if (refreshState.totalIpos > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: refreshState.processedIpos / refreshState.totalIpos,
                          backgroundColor: Colors.blue.shade100,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Last scan timestamp & Masked PAN chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (panState.hasPan && panState.pan != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.credit_card, size: 14, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Text(
                            panState.pan!.panMasked,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  if (summary?.lastScanAt != null)
                    Text(
                      'Last checked: ${DateFormat('dd MMM, hh:mm a').format(summary!.lastScanAt!.toLocal())}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Summary Metrics Grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildSummaryCard('Allotted', summary?.allottedCount ?? 0, AppColors.success, Icons.check_circle_outline),
                  _buildSummaryCard('Not Allotted', summary?.notAllottedCount ?? 0, AppColors.neutral, Icons.cancel_outlined),
                  _buildSummaryCard('Pending', summary?.pendingCount ?? 0, AppColors.warning, Icons.hourglass_empty_rounded),
                  _buildSummaryCard('Failed Checks', summary?.lookupFailedCount ?? 0, AppColors.error, Icons.error_outline),
                ],
              ),
              const SizedBox(height: 20),

              // Search Bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search IPOs or Registrars...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (val) {
                  ref.read(ipoListProvider.notifier).setSearchQuery(val);
                },
              ),
              const SizedBox(height: 12),

              // Issue Type Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All Issues'),
                      selected: ipoState.selectedIssueType == 'ALL',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('ALL'),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Mainboard'),
                      selected: ipoState.selectedIssueType == 'MAINBOARD',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('MAINBOARD'),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('SME IPOs'),
                      selected: ipoState.selectedIssueType == 'SME',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('SME'),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // IPO List View
              if (ipoState.isLoading && filteredList.isEmpty) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ] else if (filteredList.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: Column(
                    children: const [
                      Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.neutral),
                      SizedBox(height: 12),
                      Text('No IPOs found matching criteria', style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ] else ...[
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final ipo = filteredList[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      color: Colors.white,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.go('/ipo/${ipo.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                ipo.name,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                ipo.issueType,
                                                style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Registrar: ${ipo.registrar}',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (ipo.priceBand != null)
                                        Text(
                                          'Price: ${ipo.priceBand}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                                        ),
                                      if (ipo.allotmentDate != null)
                                        Text(
                                          'Allotment: ${DateFormat('dd MMM yyyy').format(ipo.allotmentDate!)}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                        ),
                                    ],
                                  ),
                                  _buildStatusBadge(ipo.status, ipo.allottedQuantity),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 80), // Padding for FloatingActionButton
            ],
          ),
        ),
      ),
    );
  }
}
