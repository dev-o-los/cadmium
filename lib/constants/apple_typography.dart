import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Central Apple Music typography system adhering to Apple Human Interface Guidelines (HIG)
/// and SF Pro design specifications for iOS Dark Mode.
abstract final class AppleTypography {
  /// Large Navigation Title (34pt, Bold, -0.4 tracking)
  /// Used for top-level screen titles: "Home", "Library", "Browse", "Search"
  static const TextStyle largeTitle = TextStyle(
    color: Colors.white,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
  );

  /// Section Header / Title 1 (16.5pt, Medium, -0.2 tracking)
  /// Used for major content section headers: "Quick Picks", "Top Songs", "Featured Albums"
  static const TextStyle sectionTitle = TextStyle(
    color: Colors.white,
    fontSize: 16.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    height: 1.25,
  );

  /// Section Eyebrow / Category Header (12pt, Semibold, 0.4 tracking, uppercase)
  /// Used above section titles or card tags: "START YOUR DAY", "FEATURED", "ALBUM"
  static const TextStyle eyebrow = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.2,
  );

  /// Section Subtitle / Description (14pt, Regular, -0.15 tracking)
  /// Used beneath section headers for explanatory context
  static const TextStyle sectionSubtitle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.15,
    height: 1.3,
  );

  /// Track Tile Title (16pt, Semibold, -0.3 tracking)
  /// Used consistently across all song rows in Home, Album, Artist, Search, and Queue
  static const TextStyle songTitle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );

  /// Track Tile Artist / Secondary Line (13.5pt, Regular, -0.1 tracking)
  /// Used consistently across all song rows beneath the title
  static const TextStyle songArtist = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Card Title for Grid / Carousel Items (15pt, Semibold, -0.25 tracking)
  /// Used for Album, Playlist, and Artist cards in carousels and grids
  static const TextStyle cardTitle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    height: 1.25,
  );

  /// Card Subtitle / Year / Artist for Grid Items (13pt, Regular, -0.1 tracking)
  /// Used under card titles in carousels and grids
  static const TextStyle cardSubtitle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Mini-Player Song Title (14pt, Semibold, -0.25 tracking)
  /// Used in the floating mini player above the bottom navigation bar
  static const TextStyle miniPlayerTitle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    height: 1.2,
  );

  /// Mini-Player Compact Inline Title (13pt, Semibold, -0.25 tracking)
  static const TextStyle miniPlayerInlineTitle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    height: 1.2,
  );

  /// Mini-Player Artist (12.5pt, Medium, -0.1 tracking, high-visibility white)
  static const TextStyle miniPlayerArtist = TextStyle(
    color: Color(0xE6FFFFFF),
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Mini-Player Compact Inline Artist (11.5pt, Medium, -0.1 tracking, high-visibility white)
  static const TextStyle miniPlayerInlineArtist = TextStyle(
    color: Color(0xE6FFFFFF),
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Now Playing Screen Song Title (22pt, Bold, -0.4 tracking)
  static const TextStyle playerTitle = TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
  );

  /// Now Playing Screen Artist (17pt, Medium, -0.25 tracking)
  static TextStyle playerArtist = TextStyle(
    color: Colors.white.withValues(alpha: 0.85),
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.25,
    height: 1.2,
  );

  /// Scrubber Timestamps / Track Durations (12.5pt, Medium, -0.1 tracking)
  static const TextStyle timestamp = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.0,
  );

  /// Explicit 'E' Badge (10pt, Bold, 0.0 tracking)
  static const TextStyle explicitBadge = TextStyle(
    color: Colors.white,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  /// Bottom Modal Sheet Header Title (17pt, Semibold, -0.35 tracking)
  static const TextStyle sheetTitle = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.35,
    height: 1.25,
  );

  /// Bottom Modal Sheet Subtitle / Artist (13.5pt, Regular, -0.1 tracking)
  static const TextStyle sheetSubtitle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.2,
  );

  /// Bottom Modal Sheet Action Tile Label (16pt, Regular, -0.2 tracking)
  static const TextStyle sheetAction = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    height: 1.25,
  );

  /// List item track number in albums (15pt, Regular / Medium)
  static TextStyle trackNumber({bool isCurrent = false}) => TextStyle(
    color: isCurrent ? Colors.white : AppColors.appleSecondaryText,
    fontSize: 15,
    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
    letterSpacing: -0.2,
  );
}

/// Standard spacing metrics matching Apple Music layout.
abstract final class AppleSpacing {
  /// Vertical spacing between title and subtitle in list tiles: 2.5px
  static const double titleToSubtitle = 2.5;

  /// Vertical spacing between section header and content: 14.0px
  static const double sectionHeaderToContent = 14.0;

  /// Vertical spacing between major sections: 32.0px
  static const double sectionSpacing = 32.0;

  /// Standard horizontal page padding: 16.0px
  static const double horizontalPadding = 16.0;
}
