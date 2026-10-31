import 'package:flutter/cupertino.dart';

/// Categories of audio output devices for UI display.
enum OutputDeviceCategory {
  speaker,
  headphones,
  bluetooth,
  usb,
  other,
}

/// Represents an audio output device (e.g., Bluetooth headphones, wired headset, built-in speaker).
class AudioDeviceItem {
  final String id;
  final String name;
  final OutputDeviceCategory category;
  final bool isSelected;

  const AudioDeviceItem({
    required this.id,
    required this.name,
    this.category = OutputDeviceCategory.speaker,
    this.isSelected = false,
  });

  bool get isBluetooth => category == OutputDeviceCategory.bluetooth;

  bool get isHeadphones =>
      category == OutputDeviceCategory.headphones ||
      category == OutputDeviceCategory.bluetooth ||
      category == OutputDeviceCategory.usb;

  bool get isSpeaker => category == OutputDeviceCategory.speaker;

  IconData get icon {
    if (isHeadphones) {
      return CupertinoIcons.headphones;
    }
    if (isSpeaker) {
      return CupertinoIcons.speaker_2_fill;
    }
    return CupertinoIcons.hifispeaker;
  }

  String get subtitle {
    switch (category) {
      case OutputDeviceCategory.bluetooth:
        return 'Connected • Bluetooth Audio';
      case OutputDeviceCategory.headphones:
        return 'Connected • Headphone Jack';
      case OutputDeviceCategory.usb:
        return 'Connected • USB Audio Output';
      case OutputDeviceCategory.speaker:
        return 'Phone Speaker';
      case OutputDeviceCategory.other:
        return 'External Audio';
    }
  }

  AudioDeviceItem copyWith({
    String? id,
    String? name,
    OutputDeviceCategory? category,
    bool? isSelected,
  }) {
    return AudioDeviceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDeviceItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          category == other.category &&
          isSelected == other.isSelected;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ category.hashCode ^ isSelected.hashCode;
}
