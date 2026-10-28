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

  Widget _buildSummaryCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: isSelected ? 6 : 4,
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
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? color : AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isSelected ? Icons.check_circle : icon,
                    size: 16,
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'FILTERED',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllottedProfitSummaryCard(IpoListState ipoState) {
    final totalProfit = ipoState.totalAllottedProfit;
    final totalInvested = ipoState.totalAllottedInvested;
    final totalValue = ipoState.totalAllottedValue;
    final totalShares = ipoState.totalAllottedShares;
    final returnPct = ipoState.totalAllottedReturnPercentage;
    final isPositive = totalProfit >= 0;
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF0F5132), const Color(0xFF198754)]
              : [const Color(0xFF842029), const Color(0xFFDC3545)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TOTAL ALLOTTED PROFIT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              if (returnPct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${returnPct.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${isPositive ? '+' : '-'}${currencyFormatter.format(totalProfit.abs())}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Calculated on $totalShares shares across ${ipoState.allottedIpos.length} allotted issue${ipoState.allottedIpos.length == 1 ? '' : 's'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildProfitMetricItem(
                  label: 'Invested',
                  value: currencyFormatter.format(totalInvested),
                ),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2)),
                _buildProfitMetricItem(
                  label: 'Current Value',
                  value: currencyFormatter.format(totalValue),
                ),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.2)),
                _buildProfitMetricItem(
                  label: 'Allotted Shares',
                  value: '$totalShares',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitMetricItem({required String label, required String value}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildAllotmentProfitCard(IpoItemModel ipo) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final shares = ipo.allottedQuantity ?? 0;
    final issuePrice = ipo.effectiveIssuePrice;
    final listingPrice = ipo.effectiveListingPrice;
    final gainPerShare = ipo.gainPerShare;
    final gainPct = ipo.gainPercentage;
    final profit = ipo.totalProfit;
    final invested = ipo.totalInvested;
    final currentValue = ipo.totalCurrentValue;

    final isProfit = (profit ?? 0) >= 0;
    final profitColor = isProfit ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (listingPrice != null ? profitColor : AppColors.primary).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (listingPrice != null ? profitColor : AppColors.primary).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Issued Price',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      issuePrice != null ? currencyFormatter.format(issuePrice) : 'N/A',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Listed Price',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listingPrice != null
                          ? currencyFormatter.format(listingPrice)
                          : 'Awaiting Listing',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: listingPrice != null ? AppColors.textPrimary : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              if (gainPerShare != null && gainPct != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: profitColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isProfit ? '+' : ''}${currencyFormatter.format(gainPerShare)}/sh',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: profitColor),
                      ),
                      Text(
                        '${isProfit ? '+' : ''}${gainPct.toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: profitColor),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$shares Shares Allotted',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  if (invested != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Invested: ${currencyFormatter.format(invested)}${currentValue != null ? " • Value: ${currencyFormatter.format(currentValue)}" : ""}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
              if (profit != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: profitColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL PROFIT',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                      ),
                      Text(
                        '${isProfit ? '+' : '-'}${currencyFormatter.format(profit.abs())}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Listing Pending',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                  ),
                ),
              ],
            ],
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

              // Summary Metrics: Focused strictly on Allotted and Pending
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Allotted',
                      count: summary?.allottedCount ?? 0,
                      color: AppColors.success,
                      icon: Icons.check_circle_outline,
                      isSelected: ipoState.selectedStatusFilter == 'ALLOTTED',
                      onTap: () {
                        final current = ipoState.selectedStatusFilter;
                        ref.read(ipoListProvider.notifier).setStatusFilter(
                          current == 'ALLOTTED' ? 'ALL' : 'ALLOTTED',
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Pending',
                      count: summary?.pendingCount ?? 0,
                      color: AppColors.warning,
                      icon: Icons.hourglass_empty_rounded,
                      isSelected: ipoState.selectedStatusFilter == 'PENDING',
                      onTap: () {
                        final current = ipoState.selectedStatusFilter;
                        ref.read(ipoListProvider.notifier).setStatusFilter(
                          current == 'PENDING' ? 'ALL' : 'PENDING',
                        );
                      },
                    ),
                  ),
                ],
              ),

              // Total Allotted Profit Summary Card (shown when Allotted filter is active)
              if (ipoState.selectedStatusFilter == 'ALLOTTED') ...[
                const SizedBox(height: 16),
                _buildAllottedProfitSummaryCard(ipoState),
              ],

              // Filter status indicator & reset
              if (ipoState.selectedStatusFilter != 'ALL') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.filter_list,
                            size: 16,
                            color: ipoState.selectedStatusFilter == 'ALLOTTED'
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Showing: ${ipoState.selectedStatusFilter.replaceAll('_', ' ')} (${filteredList.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () => ref.read(ipoListProvider.notifier).setStatusFilter('ALL'),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            children: const [
                              Icon(Icons.close, size: 14, color: AppColors.accent),
                              SizedBox(width: 4),
                              Text('Clear Filter', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

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

              // Issue Type Filter Chips: 1st Mainboard, 2nd SME, 3rd All
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Mainboard'),
                      selected: ipoState.selectedIssueType == 'MAINBOARD',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('MAINBOARD'),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('SME'),
                      selected: ipoState.selectedIssueType == 'SME',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('SME'),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('All Issues'),
                      selected: ipoState.selectedIssueType == 'ALL',
                      onSelected: (_) => ref.read(ipoListProvider.notifier).setIssueTypeFilter('ALL'),
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        ipoState.selectedStatusFilter == 'ALLOTTED'
                            ? Icons.monetization_on_outlined
                            : Icons.inventory_2_outlined,
                        size: 48,
                        color: ipoState.selectedStatusFilter == 'ALLOTTED'
                            ? AppColors.success
                            : AppColors.neutral,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ipoState.selectedStatusFilter == 'ALLOTTED'
                            ? 'No Allotted IPOs Found'
                            : 'No IPOs found matching criteria',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ipoState.selectedStatusFilter == 'ALLOTTED'
                            ? 'When an IPO is allotted to your linked PAN, its issued price, listed price, and total calculated profit will appear here.'
                            : 'Try adjusting your search query or status filter.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                      ),
                      if (ipoState.selectedStatusFilter != 'ALL') ...[
                        const SizedBox(height: 14),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                          onPressed: () => ref.read(ipoListProvider.notifier).setStatusFilter('ALL'),
                          child: const Text('Show All IPOs'),
                        ),
                      ],
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
                        side: BorderSide(
                          color: ipo.status == AllotmentStatusEnum.allotted
                              ? AppColors.success.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
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
                              if (ipo.status == AllotmentStatusEnum.allotted)
                                _buildAllotmentProfitCard(ipo),
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
