import 'dart:io';

import 'exceptions.dart';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:usb_gadget/usb_gadget.dart';

/// Parse [yamlPath] and return a [Gadget] ready for [Gadget.register], plus
/// an optional UDC name declared in the file.
///
/// Throws [ConfigException] on any structural or validation error.
Future<(Gadget gadget, String? udc)> parseGadgetSpec(String yamlPath) async {
  final String content;
  try {
    content = await File(yamlPath).readAsString();
  } on FileSystemException catch (e) {
    throw ConfigException('cannot read $yamlPath: ${e.message}');
  }

  final dynamic doc;
  try {
    doc = loadYaml(content);
  } catch (err) {
    throw ConfigException('$yamlPath: YAML syntax error: $err');
  }

  if (doc is! YamlMap) {
    throw ConfigException('$yamlPath: top-level value must be a mapping');
  }

  return _parseSpec(doc, yamlPath);
}

(Gadget, String?) _parseSpec(YamlMap doc, String src) {
  final idMap = _requireMap(doc, 'id', src);
  final id = Id(
    vendor: _intOrHex(_require(idMap, 'vendor', '$src#id'), '$src#id.vendor'),
    product: _intOrHex(
      _require(idMap, 'product', '$src#id'),
      '$src#id.product',
    ),
  );

  final dev = _optMap(doc, 'device', src);

  final stringsNode = doc['strings'] as YamlMap?;
  final strings = <USBLanguageId, GadgetStrings>{};
  if (stringsNode != null) {
    for (final entry in stringsNode.entries) {
      final lang = entry.key as String;
      final v = entry.value;
      if (v is! YamlMap) {
        throw ConfigException('$src: strings.$lang must be a mapping');
      }
      strings[_parseLangId(lang)] = GadgetStrings(
        manufacturer: v['manufacturer'] as String?,
        product: v['product'] as String?,
        serialnumber: v['serial'] as String?,
      );
    }
  }

  final fnNode = doc['functions'];
  if (fnNode is! YamlList || fnNode.isEmpty) {
    throw ConfigException('$src: "functions" must be a non-empty sequence');
  }

  final functions = <GadgetFunction>[];
  final seen = <String>{};
  for (var i = 0; i < fnNode.length; i++) {
    final entry = fnNode[i];
    if (entry is! YamlMap) {
      throw ConfigException('$src: functions[$i] must be a mapping');
    }
    final fn = _buildFunction(entry, src, i);
    if (!seen.add(fn.configfsName)) {
      throw ConfigException(
        '$src: duplicate function "${fn.configfsName}" — '
        'add a unique "name" field to each function',
      );
    }
    functions.add(fn);
  }

  final name = (doc['name'] as String?)?.isNotEmpty == true
      ? doc['name'] as String
      : p.basenameWithoutExtension(src);

  final rawUdc = doc['udc'] as String?;

  final gadget = Gadget(
    name: name,
    id: id,
    class_: _parseClass(
      dev?['class'] != null
          ? _intOrHex(dev!['class'], '$src#device.class')
          : null,
      dev?['sub_class'] != null
          ? _intOrHex(dev!['sub_class'], '$src#device.sub_class')
          : null,
      dev?['protocol'] != null
          ? _intOrHex(dev!['protocol'], '$src#device.protocol')
          : null,
    ),
    usbVersion: _parseUsbVersion(_str(dev, 'usb_version') ?? '2.0'),
    deviceRelease: dev?['device_release'] != null
        ? _intOrHex(dev!['device_release'], '$src#device.device_release')
        : 0x0100,
    strings: strings,
    configs: [
      Config(
        functions: functions,
        maxPower: MaxPower(_int(dev, 'max_power') ?? 500),
        selfPowered: _bool(dev, 'self_powered') ?? false,
        remoteWakeup: _bool(dev, 'remote_wakeup') ?? false,
      ),
    ],
  );

  return (gadget, rawUdc?.isNotEmpty == true ? rawUdc : null);
}

GadgetFunction _buildFunction(YamlMap m, String src, int idx) {
  final loc = '$src#functions[$idx]';
  final type = m['type'] as String?;
  if (type == null || type.isEmpty)
    throw ConfigException('$loc: missing "type"');

  // name defaults to "<type><idx>" when omitted
  final name = (m['name'] as String?)?.isNotEmpty == true
      ? m['name'] as String
      : '$type$idx';

  return switch (type) {
    // FunctionFs (userland) — the CLI only registers the configfs entry and
    // binds the UDC.  Descriptors are written by the in-process test code
    // (or application) after the gadget is brought up, so no descriptors are
    // needed here.
    'ffs' => FunctionFs(name: name),

    'acm' => AcmFunction(name: name, console: _bool(m, 'console')),
    'serial' ||
    'gser' => GenericSerialFunction(name: name, console: _bool(m, 'console')),
    'ecm' => EcmFunction(
      name: name,
      hostAddr: _str(m, 'host_addr'),
      devAddr: _str(m, 'dev_addr'),
    ),
    'ecm_subset' => EcmSubsetFunction(
      name: name,
      hostAddr: _str(m, 'host_addr'),
      devAddr: _str(m, 'dev_addr'),
    ),
    'eem' => EemFunction(
      name: name,
      hostAddr: _str(m, 'host_addr'),
      devAddr: _str(m, 'dev_addr'),
    ),
    'ncm' => NcmFunction(
      name: name,
      hostAddr: _str(m, 'host_addr'),
      devAddr: _str(m, 'dev_addr'),
    ),
    'rndis' => RndisFunction(
      name: name,
      hostAddr: _str(m, 'host_addr'),
      devAddr: _str(m, 'dev_addr'),
      wceis: _bool(m, 'wceis') ?? true,
    ),
    'mass_storage' || 'msd' => _buildMsd(m, name, loc),
    'hid' => _buildHid(m, name, loc),
    'midi' || 'midi2' => MidiFunction(
      name: name,
      id: _str(m, 'id') ?? 'usb-midi',
      inPorts: _int(m, 'in_ports') ?? 1,
      outPorts: _int(m, 'out_ports') ?? 1,
      buflen: _int(m, 'buflen') ?? 512,
      qlen: _int(m, 'qlen') ?? 32,
    ),
    'uac1' => _buildUac1(m, name),
    'uac2' => _buildUac2(m, name),
    'uvc' => _buildUvc(m, name, loc),
    'loopback' => LoopbackFunction(
      name: name,
      buflen: _int(m, 'buflen') ?? 4096,
      qlen: _int(m, 'qlen') ?? 32,
    ),
    'sourcesink' => SourceSinkFunction(
      name: name,
      pattern: _int(m, 'pattern') ?? 0,
      isocInterval: _int(m, 'isoc_interval') ?? 4,
      isocMaxpacket: _int(m, 'isoc_maxpacket') ?? 1024,
      isocMult: _int(m, 'isoc_mult') ?? 0,
      isocMaxburst: _int(m, 'isoc_maxburst') ?? 0,
      bulkBuflen: _int(m, 'bulk_buflen') ?? 4096,
      bulkQlen: _int(m, 'bulk_qlen') ?? 32,
      isoQlen: _int(m, 'iso_qlen') ?? 16,
    ),

    _ => throw ConfigException('$loc: unknown function type "$type"'),
  };
}

MassStorageFunction _buildMsd(YamlMap m, String name, String loc) {
  final lunsNode = m['luns'] as YamlList?;
  if (lunsNode == null || lunsNode.isEmpty) {
    throw ConfigException('$loc: mass_storage requires at least one lun');
  }
  return MassStorageFunction(
    name: name,
    stall: _bool(m, 'stall') ?? true,
    luns: [
      for (var i = 0; i < lunsNode.length; i++)
        _buildLun(lunsNode[i], '$loc.luns[$i]'),
    ],
  );
}

LunConfig _buildLun(dynamic raw, String loc) {
  if (raw is! YamlMap) throw ConfigException('$loc must be a mapping');
  return LunConfig(
    path: raw['file'] as String?,
    cdrom: raw['cdrom'] as bool? ?? false,
    ro: raw['ro'] as bool? ?? false,
    removable: raw['removable'] as bool? ?? false,
    nofua: raw['no_fua'] as bool? ?? false,
  );
}

HIDFunction _buildHid(YamlMap m, String name, String loc) {
  List<int> descriptor = const [];
  final hexStr = _str(m, 'report_desc');
  final filePath = _str(m, 'report_descriptor');

  if (hexStr != null && hexStr.isNotEmpty) {
    descriptor = _hexBytes(hexStr, '$loc.report_desc');
  } else if (filePath != null) {
    final f = File(filePath);
    if (!f.existsSync()) {
      throw ConfigException('$loc: report_descriptor not found: $filePath');
    }
    descriptor = f.readAsBytesSync();
  }

  return HIDFunction(
    name: name,
    descriptor: descriptor,
    protocol: _int(m, 'protocol') ?? 0,
    subClass: _int(m, 'subclass') ?? 0,
    reportLength: _int(m, 'report_length') ?? 64,
    noOutEndpoint: _bool(m, 'no_out_endpoint') ?? false,
  );
}

Uac1Function _buildUac1(YamlMap m, String name) {
  final cap = m['capture'] as YamlMap?;
  final pla = m['playback'] as YamlMap?;
  return Uac1Function(
    name: name,
    cChmask: _int(cap?['channel'] as YamlMap?, 'channel_mask') ?? 3,
    cSrate: _int(cap?['channel'] as YamlMap?, 'sample_rate'),
    cSsize: _int(cap?['channel'] as YamlMap?, 'sample_size'),
    cMutePresent: _bool(cap, 'mute_present'),
    cVolumePresent: _bool(cap, 'volume_present'),
    cVolumeMin: _int(cap, 'volume_min'),
    cVolumeMax: _int(cap, 'volume_max'),
    cVolumeRes: _int(cap, 'volume_resolution'),
    cVolumeName: _str(cap, 'volume_name'),
    cItName: _str(cap, 'input_terminal_name'),
    cItChName: _str(cap, 'input_terminal_channel_name'),
    cOtName: _str(cap, 'output_terminal_name'),
    pChmask: _int(pla?['channel'] as YamlMap?, 'channel_mask') ?? 3,
    pSrate: _int(pla?['channel'] as YamlMap?, 'sample_rate'),
    pSsize: _int(pla?['channel'] as YamlMap?, 'sample_size'),
    pMutePresent: _bool(pla, 'mute_present'),
    pVolumePresent: _bool(pla, 'volume_present'),
    pVolumeMin: _int(pla, 'volume_min'),
    pVolumeMax: _int(pla, 'volume_max'),
    pVolumeRes: _int(pla, 'volume_resolution'),
    pVolumeName: _str(pla, 'volume_name'),
    pItName: _str(pla, 'input_terminal_name'),
    pItChName: _str(pla, 'input_terminal_channel_name'),
    pOtName: _str(pla, 'output_terminal_name'),
    reqNumber: _int(m, 'request_number'),
    functionName: _str(m, 'function_name'),
  );
}

Uac2Function _buildUac2(YamlMap m, String name) {
  final cap = m['capture'] as YamlMap?;
  final pla = m['playback'] as YamlMap?;
  return Uac2Function(
    name: name,
    cChmask: _int(cap?['channel'] as YamlMap?, 'channel_mask') ?? 3,
    cSrate: _int(cap?['channel'] as YamlMap?, 'sample_rate') ?? 48000,
    cSsize: _int(cap?['channel'] as YamlMap?, 'sample_size') ?? 2,
    cSyncType: _int(cap, 'sync_type'),
    cHsBint: _int(cap, 'hs_interval'),
    cMutePresent: _bool(cap, 'mute_present'),
    cVolumePresent: _bool(cap, 'volume_present'),
    cVolumeMin: _int(cap, 'volume_min'),
    cVolumeMax: _int(cap, 'volume_max'),
    cVolumeRes: _int(cap, 'volume_resolution'),
    cVolumeName: _str(cap, 'volume_name'),
    cTerminalType: _int(cap, 'terminal_type'),
    cItName: _str(cap, 'input_terminal_name'),
    cItChName: _str(cap, 'input_terminal_channel_name'),
    cOtName: _str(cap, 'output_terminal_name'),
    pChmask: _int(pla?['channel'] as YamlMap?, 'channel_mask') ?? 3,
    pSrate: _int(pla?['channel'] as YamlMap?, 'sample_rate') ?? 48000,
    pSsize: _int(pla?['channel'] as YamlMap?, 'sample_size') ?? 2,
    pHsBint: _int(pla, 'hs_interval'),
    pMutePresent: _bool(pla, 'mute_present'),
    pVolumePresent: _bool(pla, 'volume_present'),
    pVolumeMin: _int(pla, 'volume_min'),
    pVolumeMax: _int(pla, 'volume_max'),
    pVolumeRes: _int(pla, 'volume_resolution'),
    pVolumeName: _str(pla, 'volume_name'),
    pTerminalType: _int(pla, 'terminal_type'),
    pItName: _str(pla, 'input_terminal_name'),
    pItChName: _str(pla, 'input_terminal_channel_name'),
    pOtName: _str(pla, 'output_terminal_name'),
    reqNumber: _int(m, 'request_number'),
    fbMax: _int(m, 'fb_max'),
    functionName: _str(m, 'function_name'),
    controlName: _str(m, 'control_name'),
    clockSourceInName: _str(m, 'clock_source_in_name'),
    clockSourceOutName: _str(m, 'clock_source_out_name'),
  );
}

UvcFunction _buildUvc(YamlMap m, String name, String loc) {
  final frameNode = m['frame'] as YamlList?;
  return UvcFunction(
    name: name,
    frames: [
      if (frameNode != null)
        for (var i = 0; i < frameNode.length; i++)
          _buildUvcFrame(frameNode[i], '$loc.frame[$i]'),
    ],
    streamingMaxpacket: _int(m, 'streaming_max_packet') ?? 3072,
    streamingMaxburst: _int(m, 'streaming_max_burst') ?? 0,
    streamingInterval: _int(m, 'streaming_interval') ?? 1,
    processingControls: _int(m, 'processing_controls'),
    cameraControls: _int(m, 'camera_controls'),
    functionName: _str(m, 'function_name'),
  );
}

UvcFrame _buildUvcFrame(dynamic raw, String loc) {
  if (raw is! YamlMap) throw ConfigException('$loc must be a mapping');
  final w =
      _int(raw, 'width') ?? (throw ConfigException('$loc: missing "width"'));
  final h =
      _int(raw, 'height') ?? (throw ConfigException('$loc: missing "height"'));
  final fmt =
      _str(raw, 'format') ?? (throw ConfigException('$loc: missing "format"'));
  final fps = (raw['fps'] as YamlList?)?.cast<int>() ?? const [30];
  return switch (fmt.toLowerCase()) {
    'yuyv' => UvcFrame.yuyv(w, h, fps),
    'mjpeg' => UvcFrame.mjpeg(w, h, fps),
    'nv12' => UvcFrame.nv12(w, h, fps),
    'h264' => UvcFrame.h264(w, h, fps),
    _ => throw ConfigException(
      '$loc: unknown format "$fmt" (yuyv/mjpeg/nv12/h264)',
    ),
  };
}

/// Maps an IETF language tag to a [USBLanguageId].
///
/// Falls back to [USBLanguageId.enUS] for unrecognised tags.
USBLanguageId _parseLangId(String tag) => switch (tag.toLowerCase()) {
  'en-us' || 'en_us' || 'en' => USBLanguageId.enUS,
  'en-gb' => USBLanguageId.enGB,
  'de' || 'de-de' => USBLanguageId.deDE,
  'fr' || 'fr-fr' => USBLanguageId.frFR,
  'ja' || 'ja-jp' => USBLanguageId.jaJP,
  'zh-cn' || 'zh' => USBLanguageId.zhCN,
  'zh-tw' => USBLanguageId.zhTW,
  'es' || 'es-es' => USBLanguageId.esES,
  'pt' || 'pt-br' => USBLanguageId.ptBR,
  'ru' || 'ru-ru' => USBLanguageId.ruRU,
  _ => USBLanguageId.enUS,
};

/// Maps a version string such as `'2.0'` to [UsbVersion].
UsbVersion _parseUsbVersion(String ver) => switch (ver) {
  '1.1' => UsbVersion.v11,
  '2.0' => UsbVersion.v20,
  '2.1' => UsbVersion.v21,
  '3.0' => UsbVersion.v30,
  '3.1' => UsbVersion.v31,
  _ => UsbVersion.v20,
};

/// Constructs a [Class] from optional raw integer fields.
///
/// When [code] is null the device defers class information to its interfaces,
/// which is correct for the vast majority of composite gadgets.
Class _parseClass(int? code, int? subClass, int? protocol) {
  if (code == null) return const Class.interfaceSpecific();
  if (code == 0xFF) return Class.vendorSpecific(subClass ?? 0, protocol ?? 0);
  final classType = ClassType.values.firstWhere(
    (c) => c.value == code,
    orElse: () => ClassType.vendorSpecific,
  );
  return Class(classType, subClass ?? 0, protocol ?? 0);
}

dynamic _require(YamlMap m, String key, String ctx) {
  final v = m[key];
  if (v == null) throw ConfigException('$ctx: missing required field "$key"');
  return v;
}

YamlMap _requireMap(YamlMap doc, String key, String src) {
  final v = doc[key];
  if (v == null) throw ConfigException('$src: missing required section "$key"');
  if (v is! YamlMap) throw ConfigException('$src: "$key" must be a mapping');
  return v;
}

YamlMap? _optMap(YamlMap doc, String key, String src) {
  final v = doc[key];
  if (v == null) return null;
  if (v is! YamlMap) throw ConfigException('$src: "$key" must be a mapping');
  return v;
}

String? _str(YamlMap? m, String key) => m?[key] as String?;

int? _int(YamlMap? m, String key) => m?[key] as int?;

bool? _bool(YamlMap? m, String key) => m?[key] as bool?;

int _intOrHex(dynamic v, String field) {
  if (v is int) return v;
  if (v is String) {
    final s = v.trim();
    final parsed = s.startsWith('0x') || s.startsWith('0X')
        ? int.tryParse(s.substring(2), radix: 16)
        : int.tryParse(s);
    if (parsed != null) return parsed;
  }
  throw ConfigException('$field: expected integer or hex string, got: $v');
}

List<int> _hexBytes(String s, String loc) {
  final clean = s
      .replaceFirst(RegExp(r'^0[xX]'), '')
      .replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd) {
    throw ConfigException('$loc: hex string must have even length');
  }
  return [
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}
