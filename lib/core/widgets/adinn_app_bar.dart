import 'package:flutter/material.dart';

import 'language_switcher.dart';

/// The app's AppBar: a normal [AppBar] plus the compact `ENG / அ` language
/// switcher as the LAST (top-right) action. Every other action keeps working
/// unchanged.
class AdinnAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdinnAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.scrolledUnderElevation,
    this.surfaceTintColor,
    this.centerTitle,
    this.titleSpacing,
    this.toolbarHeight,
    this.flexibleSpace,
    this.titleTextStyle,
    this.leadingWidth,
    this.iconTheme,
    this.shadowColor,
  });

  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final double? scrolledUnderElevation;
  final Color? surfaceTintColor;
  final bool? centerTitle;
  final double? titleSpacing;
  final double? toolbarHeight;
  final Widget? flexibleSpace;
  final TextStyle? titleTextStyle;
  final double? leadingWidth;
  final IconThemeData? iconTheme;
  final Color? shadowColor;

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) => AppBar(
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    title: title,
    actions: [...?actions, const LanguageSwitcher()],
    bottom: bottom,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    elevation: elevation,
    scrolledUnderElevation: scrolledUnderElevation,
    surfaceTintColor: surfaceTintColor,
    centerTitle: centerTitle,
    titleSpacing: titleSpacing,
    toolbarHeight: toolbarHeight,
    flexibleSpace: flexibleSpace,
    titleTextStyle: titleTextStyle,
    leadingWidth: leadingWidth,
    iconTheme: iconTheme,
    shadowColor: shadowColor,
  );
}
