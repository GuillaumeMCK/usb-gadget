import 'base.dart';

/// Audio (UAC1) function.
///
/// USB Audio Class 1 (UAC1) is widely supported by hosts including car stereos,
/// older Macs, game consoles, and embedded systems that may not support UAC2.
///
/// Fields left as `null` use the f_uac1 kernel module defaults.
/// See `drivers/usb/gadget/function/u_uac1.h`.
class Uac1Function extends KernelFunction {
  Uac1Function({
    required super.name,
    // capture channel
    this.cChmask = 3,
    this.cSrate,
    this.cSsize,
    this.cMutePresent,
    this.cVolumePresent,
    this.cVolumeMin,
    this.cVolumeMax,
    this.cVolumeRes,
    this.cVolumeName,
    this.cItName,
    this.cItChName,
    this.cOtName,
    // playback channel
    this.pChmask = 3,
    this.pSrate,
    this.pSsize,
    this.pMutePresent,
    this.pVolumePresent,
    this.pVolumeMin,
    this.pVolumeMax,
    this.pVolumeRes,
    this.pVolumeName,
    this.pItName,
    this.pItChName,
    this.pOtName,
    // general
    this.reqNumber,
    this.functionName,
  }) : super(kernelType: .uac1);

  // ── Capture ──────────────────────────────────────────────────────────────

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo, 0=disable)
  final int cChmask;

  /// Capture sample rate (Hz)
  final int? cSrate;

  /// Capture sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int? cSsize;

  /// Whether capture channel has mute control
  final bool? cMutePresent;

  /// Whether capture channel has volume control
  final bool? cVolumePresent;

  /// Capture minimum volume (in 1/256 dB)
  final int? cVolumeMin;

  /// Capture maximum volume (in 1/256 dB)
  final int? cVolumeMax;

  /// Capture volume resolution (in 1/256 dB)
  final int? cVolumeRes;

  /// Name of the capture volume control function
  final String? cVolumeName;

  /// Name of the capture input terminal
  final String? cItName;

  /// Name of the capture input terminal channel
  final String? cItChName;

  /// Name of the capture output terminal
  final String? cOtName;

  // ── Playback ─────────────────────────────────────────────────────────────

  /// Playback channel mask (bitmap: 1=left, 2=right, 3=stereo, 0=disable)
  final int pChmask;

  /// Playback sample rate (Hz)
  final int? pSrate;

  /// Playback sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int? pSsize;

  /// Whether playback channel has mute control
  final bool? pMutePresent;

  /// Whether playback channel has volume control
  final bool? pVolumePresent;

  /// Playback minimum volume (in 1/256 dB)
  final int? pVolumeMin;

  /// Playback maximum volume (in 1/256 dB)
  final int? pVolumeMax;

  /// Playback volume resolution (in 1/256 dB)
  final int? pVolumeRes;

  /// Name of the playback volume control function
  final String? pVolumeName;

  /// Name of the playback input terminal
  final String? pItName;

  /// Name of the playback input terminal channel
  final String? pItChName;

  /// Name of the playback output terminal
  final String? pOtName;

  // ── General ──────────────────────────────────────────────────────────────

  /// Number of pre-allocated requests for both capture and playback
  final int? reqNumber;

  /// The name of the interface
  final String? functionName;

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{
      'c_chmask': cChmask.toString(),
      'p_chmask': pChmask.toString(),
    };

    void opt(String key, Object? val) {
      if (val != null) attrs[key] = val.toString();
    }

    void optBool(String key, bool? val) {
      if (val != null) attrs[key] = val ? '1' : '0';
    }

    // capture
    opt('c_srate', cSrate);
    opt('c_ssize', cSsize);
    optBool('c_mute_present', cMutePresent);
    optBool('c_volume_present', cVolumePresent);
    opt('c_volume_min', cVolumeMin);
    opt('c_volume_max', cVolumeMax);
    opt('c_volume_res', cVolumeRes);
    opt('c_fu_vol_name', cVolumeName);
    opt('c_it_name', cItName);
    opt('c_it_ch_name', cItChName);
    opt('c_ot_name', cOtName);

    // playback
    opt('p_srate', pSrate);
    opt('p_ssize', pSsize);
    optBool('p_mute_present', pMutePresent);
    optBool('p_volume_present', pVolumePresent);
    opt('p_volume_min', pVolumeMin);
    opt('p_volume_max', pVolumeMax);
    opt('p_volume_res', pVolumeRes);
    opt('p_fu_vol_name', pVolumeName);
    opt('p_it_name', pItName);
    opt('p_it_ch_name', pItChName);
    opt('p_ot_name', pOtName);

    // general
    opt('req_number', reqNumber);
    opt('function_name', functionName);

    return attrs;
  }
}

/// Audio (UAC2) function.
///
/// USB Audio Class 2, higher quality than UAC1 but not supported by all hosts.
///
/// Fields left as `null` use the f_uac2 kernel module defaults.
/// See `drivers/usb/gadget/function/u_uac2.h`.
class Uac2Function extends KernelFunction {
  Uac2Function({
    required super.name,
    // capture channel
    this.cChmask = 3,
    this.cSrate = 48000,
    this.cSsize = 2,
    this.cSyncType,
    this.cHsBint,
    this.cMutePresent,
    this.cVolumePresent,
    this.cVolumeMin,
    this.cVolumeMax,
    this.cVolumeRes,
    this.cVolumeName,
    this.cTerminalType,
    this.cItName,
    this.cItChName,
    this.cOtName,
    // playback channel
    this.pChmask = 3,
    this.pSrate = 48000,
    this.pSsize = 2,
    this.pHsBint,
    this.pMutePresent,
    this.pVolumePresent,
    this.pVolumeMin,
    this.pVolumeMax,
    this.pVolumeRes,
    this.pVolumeName,
    this.pTerminalType,
    this.pItName,
    this.pItChName,
    this.pOtName,
    // general
    this.reqNumber,
    this.fbMax,
    this.functionName,
    this.controlName,
    this.clockSourceInName,
    this.clockSourceOutName,
  }) : super(kernelType: .uac2);

  // ── Capture ──────────────────────────────────────────────────────────────

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo, 0=disable)
  final int cChmask;

  /// Capture sample rate (Hz)
  final int cSrate;

  /// Capture sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int cSsize;

  /// Capture audio sync type
  final int? cSyncType;

  /// Capture bInterval for HS/SS (1-4: fixed, 0: auto)
  final int? cHsBint;

  /// Whether capture channel has mute control
  final bool? cMutePresent;

  /// Whether capture channel has volume control
  final bool? cVolumePresent;

  /// Capture minimum volume (in 1/256 dB)
  final int? cVolumeMin;

  /// Capture maximum volume (in 1/256 dB)
  final int? cVolumeMax;

  /// Capture volume resolution (in 1/256 dB)
  final int? cVolumeRes;

  /// Name of the capture volume control function
  final String? cVolumeName;

  /// Capture terminal type
  final int? cTerminalType;

  /// Name of the capture input terminal
  final String? cItName;

  /// Name of the capture input terminal channel
  final String? cItChName;

  /// Name of the capture output terminal
  final String? cOtName;

  // ── Playback ─────────────────────────────────────────────────────────────

  /// Playback channel mask (bitmap: 1=left, 2=right, 3=stereo, 0=disable)
  final int pChmask;

  /// Playback sample rate (Hz)
  final int pSrate;

  /// Playback sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int pSsize;

  /// Playback bInterval for HS/SS (1-4: fixed, 0: auto)
  final int? pHsBint;

  /// Whether playback channel has mute control
  final bool? pMutePresent;

  /// Whether playback channel has volume control
  final bool? pVolumePresent;

  /// Playback minimum volume (in 1/256 dB)
  final int? pVolumeMin;

  /// Playback maximum volume (in 1/256 dB)
  final int? pVolumeMax;

  /// Playback volume resolution (in 1/256 dB)
  final int? pVolumeRes;

  /// Name of the playback volume control function
  final String? pVolumeName;

  /// Playback terminal type
  final int? pTerminalType;

  /// Name of the playback input terminal
  final String? pItName;

  /// Name of the playback input terminal channel
  final String? pItChName;

  /// Name of the playback output terminal
  final String? pOtName;

  // ── General ──────────────────────────────────────────────────────────────

  /// Number of pre-allocated requests for both capture and playback
  final int? reqNumber;

  /// Maximum extra bandwidth in async mode
  final int? fbMax;

  /// The name of the interface
  final String? functionName;

  /// Topology control name
  final String? controlName;

  /// Name of the input clock source
  final String? clockSourceInName;

  /// Name of the output clock source
  final String? clockSourceOutName;

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
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{
      'c_chmask': cChmask.toString(),
      'c_srate': cSrate.toString(),
      'c_ssize': cSsize.toString(),
      'p_chmask': pChmask.toString(),
      'p_srate': pSrate.toString(),
      'p_ssize': pSsize.toString(),
    };

    void opt(String key, Object? val) {
      if (val != null) attrs[key] = val.toString();
    }

    void optBool(String key, bool? val) {
      if (val != null) attrs[key] = val ? '1' : '0';
    }

    // capture optional
    opt('c_sync', cSyncType);
    opt('c_hs_bint', cHsBint);
    optBool('c_mute_present', cMutePresent);
    optBool('c_volume_present', cVolumePresent);
    opt('c_volume_min', cVolumeMin);
    opt('c_volume_max', cVolumeMax);
    opt('c_volume_res', cVolumeRes);
    opt('c_fu_vol_name', cVolumeName);
    opt('c_terminal_type', cTerminalType);
    opt('c_it_name', cItName);
    opt('c_it_ch_name', cItChName);
    opt('c_ot_name', cOtName);

    // playback optional
    opt('p_hs_bint', pHsBint);
    optBool('p_mute_present', pMutePresent);
    optBool('p_volume_present', pVolumePresent);
    opt('p_volume_min', pVolumeMin);
    opt('p_volume_max', pVolumeMax);
    opt('p_volume_res', pVolumeRes);
    opt('p_fu_vol_name', pVolumeName);
    opt('p_terminal_type', pTerminalType);
    opt('p_it_name', pItName);
    opt('p_it_ch_name', pItChName);
    opt('p_ot_name', pOtName);

    // general optional
    opt('req_number', reqNumber);
    opt('fb_max', fbMax);
    opt('function_name', functionName);
    opt('if_ctrl_name', controlName);
    opt('clksrc_in_name', clockSourceInName);
    opt('clksrc_out_name', clockSourceOutName);

    return attrs;
  }
}
