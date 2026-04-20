import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FinanceShell extends StatelessWidget {
  final Widget child;
  const FinanceShell({super.key, required this.child});

  static const _items = [
    _NavItem(
      'Dashboard',
      Icons.account_balance_wallet_outlined,
      '/finance/dashboard',
    ),
    _NavItem(
      'Donations',
      Icons.volunteer_activism_outlined,
      '/finance/donations',
    ),
    _NavItem('Reconcile', Icons.rule_folder_outlined, '/finance/reconcile'),
    _NavItem('Reports', Icons.summarize_outlined, '/finance/reports'),
    _NavItem(
      'Notifications',
      Icons.notifications_outlined,
      '/finance/notifications',
    ),
    _NavItem('Profile', Icons.person_outline, '/finance/profile'),
  ];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _items.length; i++) {
      if (location.startsWith(_items[i].route)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final idx = _indexFromLocation(location);
    final isWide = MediaQuery.of(context).size.width >= 1000;

    void goSafe(String route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(route);
      });
    }

    Widget wrapContent(Widget child) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final pad = w < 480 ? 12.0 : 16.0;
          final content = Padding(padding: EdgeInsets.all(pad), child: child);

          if (w >= 1400) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: content,
              ),
            );
          }

          return content;
        },
      );
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 270,
              child: _Sidebar(
                selectedIndex: idx,
                onSelect: (i) => goSafe(_items[i].route),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: wrapContent(child)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_items[idx].label), actions: []),
      body: wrapContent(child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => goSafe(_items[i].route),
        destinations: [
          for (final item in _items)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _Sidebar({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Finance',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: FinanceShell._items.length,
                itemBuilder: (context, i) {
                  final item = FinanceShell._items[i];
                  final selected = i == selectedIndex;
                  return ListTile(
                    selected: selected,
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    onTap: () => onSelect(i),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}
