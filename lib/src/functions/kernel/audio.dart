import 'base.dart';

/// Audio (UAC1) function.
class Uac1Function extends KernelFunction {
  Uac1Function({
    required super.name,
    this.cChmask = 3,
    this.pChmask = 3,
    this.reqNumber = 2,
  }) : super(kernelType: .uac1);

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo)
  final int cChmask;

  /// Playback channel mask
  final int pChmask;

  /// Number of pre-allocated requests
  final int reqNumber;

  @override
  Map<String, String> getConfigAttributes() => {
    'c_chmask': cChmask.toString(),
    'p_chmask': pChmask.toString(),
    'req_number': reqNumber.toString(),
  };
}

/// Audio (UAC2) function.
class Uac2Function extends KernelFunction {
  Uac2Function({
    required super.name,
    this.cChmask = 3,
    this.pChmask = 3,
    this.cSrate = 48000,
    this.pSrate = 48000,
    this.cSsize = 2,
    this.pSsize = 2,
    this.reqNumber = 2,
  }) : super(kernelType: .uac2);

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo)
  final int cChmask;

  /// Playback channel mask
  final int pChmask;

  /// Capture sample rate (Hz)
  final int cSrate;

  /// Playback sample rate (Hz)
  final int pSrate;

  /// Capture sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int cSsize;

  /// Playback sample size (bytes)
  final int pSsize;

  /// Number of pre-allocated requests
  final int reqNumber;

  @override
  bool validate() {
    if (cSrate <= 0 || cSrate > 192000) {
      log?.error('Invalid capture sample rate: $cSrate');
      return false;
    }
    if (pSrate <= 0 || pSrate > 192000) {
      log?.error('Invalid playback sample rate: $pSrate');
      return false;
    }
    if (![2, 3, 4].contains(cSsize)) {
      log?.error('Invalid capture sample size: $cSsize');
      return false;
    }
    if (![2, 3, 4].contains(pSsize)) {
      log?.error('Invalid playback sample size: $pSsize');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'c_chmask': cChmask.toString(),
    'p_chmask': pChmask.toString(),
    'c_srate': cSrate.toString(),
    'p_srate': pSrate.toString(),
    'c_ssize': cSsize.toString(),
    'p_ssize': pSsize.toString(),
    'req_number': reqNumber.toString(),
  };
}
