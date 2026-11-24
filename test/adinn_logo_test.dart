import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signage_recce/core/widgets/common_widgets.dart';

/// The app shows the ORIGINAL Adinn logo (the website's own artwork rendered to PNG), not a redrawn text version.

void main() {
  testWidgets('AdinnLogo draws the original logo image with its name for screen readers', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AdinnLogo(size: 40)))));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, adinnLogoAsset);
    expect(image.semanticLabel, 'Adinn Advertising Services');
    expect(image.height, closeTo(58, 0.01)); // 1.45 x size, the width follows the logo's own shape
    expect(find.text('adinn'), findsNothing); // the old text-and-square imitation is gone
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a coloured background the logo sits on a white plate and keeps its own colours', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AdinnLogo(size: 26, light: true)))));
    final plate = tester.widget<Container>(find.ancestor(of: find.byType(Image), matching: find.byType(Container)).first);
    expect((plate.decoration as BoxDecoration).color, Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the logo is loaded before the first screen: the splash has it in its first frame and no second copy is made', (tester) async {
    await tester.runAsync(() async {
      imageCache.clear();
      await preloadAdinnLogo();
    });
    final key = await tester.runAsync(() => const AssetImage(adinnLogoAsset).obtainKey(ImageConfiguration.empty));
    expect(imageCache.containsKey(key!), isTrue);
    expect(imageCache.currentSize, 1);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AdinnLogo(size: 26)))));
    expect(imageCache.currentSize, 1); // the logo on screen used the preloaded one (same cache entry)
    // the box has the logo's own shape from the first frame
    final box = tester.getSize(find.byType(Image));
    expect(box.height, closeTo(26 * 1.45, 0.01));
    expect(box.width, closeTo(26 * 1.45 * 125 / 47, 0.5));
    expect(tester.takeException(), isNull);
  });

  test('the logo files are in the project: the full logo (website) and the "A" mark, plus the launcher icons', () {
    for (final f in [
      'assets/images/adinn_logo.png',
      'assets/images/adinn_mark.png',
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
    ]) {
      expect(File(f).existsSync(), isTrue, reason: f);
      expect(File(f).lengthSync(), greaterThan(300), reason: f);
    }
    expect(File('android/app/src/main/res/drawable/ic_launcher_foreground.xml').existsSync(), isFalse); // the old Flutter vector is gone
  });
}
