// lib/enums/sound_setting.dart
enum SoundSetting {
  default_sound,
  alert,
  beep,
  chime,
  soft,
  siren,
  alarm,
  warning,
  none,
}

// ฟังก์ชันสำหรับแปลง string เป็น SoundSetting
SoundSetting stringToSoundSetting(String value) {
  switch (value) {
    case 'default':
      return SoundSetting.default_sound;
    case 'alert':
      return SoundSetting.alert;
    case 'beep':
      return SoundSetting.beep;
    case 'chime':
      return SoundSetting.chime;
    case 'soft':
      return SoundSetting.soft;
    case 'siren':
      return SoundSetting.siren;
    case 'alarm':
      return SoundSetting.alarm;
    case 'warning':
      return SoundSetting.warning;
    case 'none':
      return SoundSetting.none;
    default:
      return SoundSetting.default_sound;
  }
}

// ฟังก์ชันสำหรับแปลง SoundSetting เป็น string
String soundSettingToString(SoundSetting setting) {
  switch (setting) {
    case SoundSetting.default_sound:
      return 'default';
    case SoundSetting.alert:
      return 'alert';
    case SoundSetting.beep:
      return 'beep';
    case SoundSetting.chime:
      return 'chime';
    case SoundSetting.soft:
      return 'soft';
    case SoundSetting.siren:
      return 'siren';
    case SoundSetting.alarm:
      return 'alarm';
    case SoundSetting.warning:
      return 'warning';
    case SoundSetting.none:
      return 'none';
  }
} 