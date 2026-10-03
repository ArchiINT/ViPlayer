import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/empty_state.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSearch)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.manage_search,
              title: l10n.navSearch,
              message: l10n.searchEmptyBody,
            ),
          ),
        ],
      ),
    );
  }
}
