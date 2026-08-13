import 'package:bentago/main.dart' as app;
import 'package:bentago/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Drives the app through the demo, one "beat" at a time, and reports when each
/// beat began so the pipeline can lay the narration over the recording without
/// anybody aligning anything by hand.
///
/// Each beat runs for exactly as long as its narration clip, passed in by
/// `tool/demo/narrate.ps1` as
/// `--dart-define=BENTAGO_BEATS=intro=7400,ringup=9100,...`. Taps inside a beat
/// are spaced evenly across that time, so the picture never races ahead of the
/// voice or sits frozen waiting for it.
///
/// Run through the pipeline, not by hand:
///     powershell -File tool\demo\make-demo.ps1
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Beat id -> how long that beat should last, in milliseconds.
  final durations = _parseBeats(
    const String.fromEnvironment('BENTAGO_BEATS'),
  );

  /// What the editor needs back: when each beat actually started, on the
  /// device's clock. `record.ps1` measures the device-to-host clock offset
  /// separately, so these convert cleanly to positions in the video file.
  final marks = <Map<String, Object?>>[];

  testWidgets('records the BentaGo product demo', (tester) async {
    app.main();

    // Wait for the price list to actually be on screen rather than for a fixed
    // number of seconds: the demo seeder writes six weeks of sales before the
    // first frame, and how long that takes depends on the machine.
    //
    // The recorder attaches when the app window takes focus, which happens
    // before this resolves, so the hold afterwards is what guarantees the
    // recording has started by the time the first beat does.
    await _waitFor(tester, find.byType(ProductAvatar));
    await _hold(tester, const Duration(milliseconds: 3200));

    /// Runs one beat: stamps its start, then spends the beat's whole allotted
    /// time on [steps], padding whatever is left over at the end.
    Future<void> beat(
      String id,
      List<Future<void> Function()> steps,
    ) async {
      final total = Duration(milliseconds: durations[id] ?? 6000);
      final clock = Stopwatch()..start();
      final startedAt = DateTime.now().millisecondsSinceEpoch;

      for (var i = 0; i < steps.length; i++) {
        await steps[i]();
        final left = total - clock.elapsed;
        final stepsLeft = steps.length - i - 1;
        // Share the remaining time out over the steps still to come; the last
        // step holds whatever is left so the beat lands on its duration.
        final pause = stepsLeft == 0 ? left : left ~/ (stepsLeft + 1);
        if (pause > Duration.zero) await _hold(tester, pause);
      }
      if (steps.isEmpty) await _hold(tester, total);

      marks.add({
        'id': id,
        'startedAtMs': startedAt,
        'endedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // 1. The screen the app opens on, with the day's takings already on it.
    await beat('intro', []);

    // 2. Ring up three things. Tapping a tile is the whole interaction.
    await beat('ringup', [
      () => _tapProduct(tester, 0),
      () => _tapProduct(tester, 3),
      () => _tapProduct(tester, 7),
      // Open the basket so the lines and the running total are both visible.
      () => _tapText(tester, '3 items'),
    ]);

    // 3. Take it as cash. The day's total at the top moves immediately.
    await beat('cash', [
      () => _tapText(tester, 'Done'),
    ]);

    // 4. The same sale on credit: choosing Credit asks who owes it.
    await beat('utang', [
      () => _tapProduct(tester, 1),
      () => _tapProduct(tester, 5),
      () => _tapText(tester, 'Credit'),
      () => _tapText(tester, 'Aling Nena'),
      () => _tapText(tester, 'Done'),
    ]);

    // 5. Dashboard: today, this week, this month.
    await beat('dashboard', [
      () => _tapNav(tester, 'Dashboard'),
      () => _scroll(tester, -300),
      () => _scroll(tester, -300),
    ]);

    // 6. The price list, with the margin on every line.
    await beat('products', [
      () => _tapNav(tester, 'Products'),
      () => _scroll(tester, -320),
    ]);

    // 7. The credit book, then one person's page.
    await beat('credit', [
      () => _tapNav(tester, 'Credit'),
      () => _tapText(tester, 'Aling Nena'),
    ]);

    // 8. Settle the tab. The dialog arrives pre-filled with what is owed, so
    //    the whole thing is two taps.
    await beat('payment', [
      () => _tapText(tester, 'Payment'),
      () => _tapText(tester, 'Record payment'),
      () => _back(tester),
    ]);

    // 9. Reports, and the same numbers over a different window.
    await beat('reports', [
      () => _tapNav(tester, 'Reports'),
      () => _tapText(tester, 'Week'),
      () => _scroll(tester, -340),
      () => _scroll(tester, -340),
    ]);

    // 10. Every transaction, as a table -- where a wrong number gets chased.
    await beat('records', [
      () => _tapTooltip(tester, 'Sales records'),
      () => _scroll(tester, -280),
      () => _back(tester),
    ]);

    // 11. The month as a spreadsheet or a PDF, written to the phone.
    await beat('export', [
      () => _tapTooltip(tester, 'Export report'),
      () => _scroll(tester, -240),
      () => _back(tester),
    ]);

    // 12. Back where it started.
    await beat('outro', [
      () => _tapNav(tester, 'Sell'),
    ]);

    binding.reportData = <String, Object?>{'marks': marks};
  }, timeout: const Timeout(Duration(minutes: 12)));
}

/// Parses `intro=7400,ringup=9100` into a lookup. An unknown or missing beat
/// falls back to six seconds, so the flow still runs if the narration is not
/// generated yet.
Map<String, int> _parseBeats(String spec) {
  final durations = <String, int>{};
  for (final pair in spec.split(',')) {
    final parts = pair.split('=');
    if (parts.length != 2) continue;
    final ms = int.tryParse(parts[1].trim());
    if (ms != null) durations[parts[0].trim()] = ms;
  }
  return durations;
}

/// Real time passing, with frames rendering throughout.
///
/// Deliberately not `pumpAndSettle`: several screens show a
/// `CircularProgressIndicator` while their query runs, and settling never
/// completes against an animation that repeats forever.
Future<void> _hold(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Pumps until [finder] matches something, or gives up with a clear message.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${timeout.inSeconds}s waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The pause after a tap: long enough for the route, sheet or query to land.
Future<void> _react(WidgetTester tester) =>
    _hold(tester, const Duration(milliseconds: 900));

/// Text anywhere except the bottom navigation bar.
///
/// Needed because the bar's labels collide with the interface behind it --
/// 'Credit' is both a tab and a payment method, and every screen's app-bar title
/// repeats its tab's label.
Finder _bodyText(String text) => find.byElementPredicate(
      (element) {
        final widget = element.widget;
        if (widget is! Text || widget.data != text) return false;
        return element.findAncestorWidgetOfExactType<NavigationBar>() == null;
      },
      // `describeMatch` is what the deprecation points at, but
      // byElementPredicate does not accept it on this Flutter version.
      // ignore: deprecated_member_use
      description: 'Text("$text") outside the navigation bar',
    );

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = _bodyText(text);
  expect(
    finder,
    findsAtLeastNWidgets(1),
    reason: 'demo flow expected to find "$text" on screen',
  );
  await _reveal(tester, finder.first);
  await tester.tap(finder.first, warnIfMissed: false);
  await _react(tester);
}

/// Scrolls [finder] into view when it sits in a list.
///
/// Worth the trouble because taps here pass `warnIfMissed: false` -- without
/// this, a target that had scrolled off (a name low down the customer picker
/// once the keyboard is up, say) would be "tapped" at a coordinate outside the
/// viewport and the demo would carry on as though it had worked.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  try {
    await tester.ensureVisible(finder);
  } on Object {
    // Nothing scrollable above it -- a button in a bottom bar, for instance.
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    ),
    warnIfMissed: false,
  );
  await _react(tester);
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip), warnIfMissed: false);
  await _react(tester);
}

/// Taps the nth product tile on the sell screen.
///
/// By position rather than by name: the tiles carry no keys, and the grid's
/// order depends on what the price list happens to contain. Every tile has
/// exactly one [ProductAvatar], and tapping it lands inside the tile's InkWell.
Future<void> _tapProduct(WidgetTester tester, int index) async {
  final tiles = find.byType(ProductAvatar);
  expect(
    tiles,
    findsAtLeastNWidgets(index + 1),
    reason: 'demo flow expected at least ${index + 1} product tiles',
  );
  await _reveal(tester, tiles.at(index));
  await tester.tap(tiles.at(index), warnIfMissed: false);
  await _react(tester);
}

/// A slow, deliberate scroll -- a flick blurs into unreadable video.
///
/// Dragged from a screen coordinate rather than a `Scrollable` finder: several
/// screens put a horizontal chart strip above their vertical list, and
/// `find.byType(Scrollable).first` grabs the wrong one.
Future<void> _scroll(WidgetTester tester, double dy) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.timedDragFrom(
    Offset(size.width / 2, size.height * 0.62),
    Offset(0, dy),
    const Duration(milliseconds: 900),
  );
  await _react(tester);
}

Future<void> _back(WidgetTester tester) async {
  final state = tester.state<NavigatorState>(find.byType(Navigator).first);
  state.pop();
  await _react(tester);
}
