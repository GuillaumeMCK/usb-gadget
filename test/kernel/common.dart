import 'package:usb_gadget/usb_gadget.dart';

export 'package:usb_gadget/usb_gadget.dart';
export '../common.dart';

Gadget kernelTestGadget(String name, GadgetFunction fn) => Gadget(
  name: name,
  id: const Id(vendor: 0x1234, product: 0xFFFF),
  strings: {
    USBLanguageId.enUS: const GadgetStrings(
      manufacturer: 'Test',
      product: 'Kernel Function Test',
      serialnumber: 'KFT-001',
    ),
  },
  configs: [
    Config(functions: [fn]),
  ],
);

class MinimalKernelFn extends KernelFunction {
  MinimalKernelFn({required super.name, required super.kernelType});

  @override
  Map<String, String> getConfigAttributes() => {};

  @override
  void checkDirectoryExists(String path) {}
}
