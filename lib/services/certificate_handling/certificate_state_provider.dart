import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'certificate_picker_service.dart';

class CertificateState {
  final String? selectedAlias;
  final bool isCertificateSelected;
  final bool isCertificateVerified;
  final String? error;

  CertificateState({
    this.selectedAlias,
    this.isCertificateSelected = false,
    this.isCertificateVerified = false,
    this.error,
  });

  CertificateState copyWith({
    String? selectedAlias,
    bool? isCertificateSelected,
    bool? isCertificateVerified,
    String? error,
  }) {
    return CertificateState(
      selectedAlias: selectedAlias ?? this.selectedAlias,
      isCertificateSelected:
          isCertificateSelected ?? this.isCertificateSelected,
      isCertificateVerified:
          isCertificateVerified ?? this.isCertificateVerified,
      error: error,
    );
  }
}

class CertificateStateNotifier extends StateNotifier<CertificateState> {
  CertificateStateNotifier() : super(CertificateState());

  Future<bool> selectCertificate() async {
    state = state.copyWith(error: null);
    try {
      final alias = await CertificatePickerService.pickCertificate();
      if (alias != null) {
        await CertificatePickerService.setupClientAuth(alias);
        final isAvailable =
            await CertificatePickerService.isCertificateAvailable(alias);
        state = state.copyWith(
          selectedAlias: alias,
          isCertificateSelected: true,
          isCertificateVerified: isAvailable,
          error:
              isAvailable ? null : 'Certificate not verified after selection',
        );
        return isAvailable;
      } else {
        state = state.copyWith(
          selectedAlias: null,
          isCertificateSelected: false,
          isCertificateVerified: false,
          error: 'Certificate access required. Please grant permission.',
        );
        return false;
      }
    } catch (e) {
      if (e.toString().contains('NO_CERTIFICATE_STORED')) {
        try {
          final alias = await CertificatePickerService.selectCertificate();
          if (alias != null) {
            await CertificatePickerService.setupClientAuth(alias);
            final isAvailable =
                await CertificatePickerService.isCertificateAvailable(alias);
            state = state.copyWith(
              selectedAlias: alias,
              isCertificateSelected: true,
              isCertificateVerified: isAvailable,
              error: isAvailable
                  ? null
                  : 'Certificate not verified after selection',
            );
            return isAvailable;
          }
        } catch (selectionError) {
          state = state.copyWith(
            selectedAlias: null,
            isCertificateSelected: false,
            isCertificateVerified: false,
            error: 'Certificate selection failed: $selectionError',
          );
          return false;
        }
      } else if (e.toString().contains('CERTIFICATE_NOT_INSTALLED') ||
          e.toString().contains('CERTIFICATE_NOT_FOUND')) {
        try {
          final alias =
              await CertificatePickerService.requestCertificateAccess();
          if (alias != null) {
            await CertificatePickerService.setupClientAuth(alias);
            final isAvailable =
                await CertificatePickerService.isCertificateAvailable(alias);
            state = state.copyWith(
              selectedAlias: alias,
              isCertificateSelected: true,
              isCertificateVerified: isAvailable,
              error: isAvailable
                  ? null
                  : 'Certificate not verified after permission grant',
            );
            return isAvailable;
          }
        } catch (permissionError) {
          state = state.copyWith(
            selectedAlias: null,
            isCertificateSelected: false,
            isCertificateVerified: false,
            error: 'Certificate permission denied: $permissionError',
          );
          return false;
        }
      }

      state = state.copyWith(
        selectedAlias: null,
        isCertificateSelected: false,
        isCertificateVerified: false,
        error: 'Certificate selection failed: $e',
      );
      return false;
    }
  }

  Future<void> clearCertificate() async {
    await CertificatePickerService.clearCertificate();
    state = CertificateState();
  }

  void syncWithNativeState() {
    state = CertificateState();
  }

  Future<bool> selectCertificateManually() async {
    state = state.copyWith(error: null);
    try {
      final alias = await CertificatePickerService.selectCertificate();
      if (alias != null) {
        await CertificatePickerService.setupClientAuth(alias);
        final isAvailable =
            await CertificatePickerService.isCertificateAvailable(alias);
        state = state.copyWith(
          selectedAlias: alias,
          isCertificateSelected: true,
          isCertificateVerified: isAvailable,
          error: isAvailable ? null : 'Certificate not verified after selection',
        );
        return isAvailable;
      } else {
        state = state.copyWith(
          selectedAlias: null,
          isCertificateSelected: false,
          isCertificateVerified: false,
          error: 'Certificate selection cancelled',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        selectedAlias: null,
        isCertificateSelected: false,
        isCertificateVerified: false,
        error: 'Certificate selection failed: $e',
      );
      return false;
    }
  }
}

final certificateStateProvider =
    StateNotifierProvider<CertificateStateNotifier, CertificateState>((ref) {
  return CertificateStateNotifier();
});

