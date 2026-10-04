import '../../core/sync/sync_service.dart';
import '../../l10n/generated/app_localizations.dart';

extension SyncTexts on AppLocalizations {
  String syncFailure(SyncFailure reason) => switch (reason) {
    SyncFailure.unreachable => syncErrUnreachable,
    SyncFailure.notOnNetwork => syncErrNotOnNetwork,
    SyncFailure.refused => syncErrRefused,
    SyncFailure.wrongCode => syncWrongCode,
    SyncFailure.notViPlayer => syncErrNotViPlayer,
    SyncFailure.isSelf => syncErrSelf,
    SyncFailure.failed => syncErrFailed,
  };
}
