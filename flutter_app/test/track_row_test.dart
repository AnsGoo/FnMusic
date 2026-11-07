import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/data/models.dart';
import 'package:fnmusic/ui/widgets.dart';

void main() {
  const track = Track(id: 't1', title: '第一首');

  Future<void> pumpRow(
    WidgetTester tester, {
    bool showCover = true,
    bool active = false,
    bool playing = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackRow(
            track: track,
            index: 0,
            showCover: showCover,
            active: active,
            playing: playing,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('renders a cover thumbnail with the library list', (tester) async {
    await pumpRow(tester);

    expect(find.byType(CoverImage), findsOneWidget);
    expect(tester.getSize(find.byType(CoverImage)).width, 44);
    expect(tester.getSize(find.byType(TrackRow)).height, 60);
  });

  testWidgets('drops the thumbnail when the album header already shows it', (
    tester,
  ) async {
    await pumpRow(tester, showCover: false);

    expect(find.byType(CoverImage), findsNothing);
    expect(tester.getSize(find.byType(TrackRow)).height, 52);
  });

  testWidgets('marks the playing track with the volume glyph', (tester) async {
    await pumpRow(tester, active: true, playing: true);

    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });
}
