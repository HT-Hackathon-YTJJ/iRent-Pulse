/// 車牌辨識 — picked per platform at compile time, the same way [car_detector.dart]
/// picks its detector.
///
/// Mobile gets [plate_reader_mlkit.dart]: Google ML Kit's on-device Latin text
/// recogniser. That is a deliberate choice over a dedicated ALPR network —
///
/// * **It ships as a solved problem.** A two-stage ALPR (a detector for the
///   plate rectangle, then a character recogniser) means finding weights with a
///   usable licence, converting them to TFLite, and tuning two models against
///   Taiwanese plates we do not have a dataset for. ML Kit is one call, already
///   tuned for text photographed in the wild, and free.
/// * **We already know where to look.** The COCO detector hands us the car's
///   bounding box every frame, so the "find the plate" stage a dedicated ALPR
///   would spend its first network on is answered by cropping to the car.
/// * **It is fast enough and no faster than it needs to be.** ~50–150 ms per
///   call on a mid-range handset, run at 1.5 Hz on a crop rather than per frame.
///   The check has two seconds to reach an answer while the driver lines up the
///   shot; it is not in the frame budget.
///
/// The failure mode is what makes it acceptable: ML Kit reads any text, so it
/// returns the badges and stickers along with the plate. Sorting that out is
/// [plate.dart]'s job, and it is a much easier problem than character
/// recognition.
///
/// Web (and desktop, at runtime) gets [plate_reader_stub.dart] — a reader that
/// never loads, which leaves the plate check permanently [PlateMatch.unknown]
/// and L0 exactly as it was before this file existed.
library;

export 'plate.dart';
export 'plate_reader_stub.dart'
    if (dart.library.io) 'plate_reader_mlkit.dart';
