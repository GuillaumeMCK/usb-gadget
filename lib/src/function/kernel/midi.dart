import 'base.dart';

/// MIDI function (Musical Instrument Digital Interface).
class MidiFunction extends KernelFunction {
  MidiFunction({
    required super.name,
    this.id = 'usb-midi',
    this.inPorts = 1,
    this.outPorts = 1,
    this.buflen = 512,
    this.qlen = 32,
  }) : super(kernelType: .midi);

  /// MIDI device identifier string
  final String id;

  /// Number of MIDI input ports (device to host)
  final int inPorts;

  /// Number of MIDI output ports (host to device)
  final int outPorts;

  /// Buffer length for each port
  final int buflen;

  /// Request queue length
  final int qlen;

  @override
  bool validate() {
    if (inPorts < 0 || inPorts > 16) {
      log?.error('Invalid input ports: $inPorts (must be 0-16)');
      return false;
    }
    if (outPorts < 0 || outPorts > 16) {
      log?.error('Invalid output ports: $outPorts (must be 0-16)');
      return false;
    }
    if (buflen <= 0 || buflen > 4096) {
      log?.error('Invalid buffer length: $buflen');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'id': id,
    'in_ports': inPorts.toString(),
    'out_ports': outPorts.toString(),
    'buflen': buflen.toString(),
    'qlen': qlen.toString(),
  };

  /// Gets the ALSA sequencer device path.
  ///
  /// Note: MIDI devices use ALSA sequencer (/dev/snd/seq) rather than
  /// direct device files. The card number can be read from 'alsa_card' attribute.
  ///
  /// Returns the ALSA card number as a string, or null if not available.
  String? getMidiCardNumber() {
    if (!prepared) return null;
    try {
      return readAttribute('alsa_card');
    } catch (_) {
      return null;
    }
  }
}
