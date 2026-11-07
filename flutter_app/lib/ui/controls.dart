/// Inputs and controls tuned for a pointer-driven desktop window: 38dp fields,
/// a 34dp search pill and hairline sliders instead of Material's 56dp forms and
/// 20dp-thumb sliders.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class MfField extends StatefulWidget {
  const MfField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.password = false,
    this.onSubmit,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final bool password;
  final VoidCallback? onSubmit;

  @override
  State<MfField> createState() => _FnFieldState();
}

class _FnFieldState extends State<MfField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void didUpdateWidget(covariant MfField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: _focused ? Mf.accent : Mf.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Mf.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Mf.accent : Mf.border,
            ),
          ),
          child: Center(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              obscureText: widget.password,
              onSubmitted: (_) => widget.onSubmit?.call(),
              cursorColor: Mf.accent,
              cursorWidth: 1.4,
              style: const TextStyle(fontSize: 13, color: Mf.text),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: const TextStyle(color: Mf.faint, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MfSearchField extends StatefulWidget {
  const MfSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder = '搜索歌曲、专辑…',
    this.onSubmit,
    this.onClear,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final VoidCallback? onSubmit;
  final VoidCallback? onClear;

  @override
  State<MfSearchField> createState() => _FnSearchFieldState();
}

class _FnSearchFieldState extends State<MfSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!mounted) return;
      setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void didUpdateWidget(covariant MfSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused
        ? Mf.accent
        : (_hovered ? Mf.muted : Mf.border);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 3),
        decoration: BoxDecoration(
          color: Mf.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 15,
              color: _focused ? Mf.muted : Mf.faint,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Center(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: widget.onChanged,
                  onSubmitted: (_) => widget.onSubmit?.call(),
                  textInputAction: TextInputAction.search,
                  cursorColor: Mf.accent,
                  cursorWidth: 1.4,
                  style: const TextStyle(fontSize: 12.5, color: Mf.text),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: const TextStyle(
                      color: Mf.faint,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.value.isNotEmpty && widget.onClear != null)
              MfIconButton(
                icon: Icons.close,
                size: 22,
                glyph: 12,
                onTap: () {
                  widget.onClear?.call();
                  _controller.clear();
                },
              )
            else
              const SizedBox(width: 7),
          ],
        ),
      ),
    );
  }
}

/// The one filled call to action: an icon-and-label pill that lifts on hover
/// and settles on press, so it reads as a button rather than a coloured label.
class MfPrimaryButton extends StatefulWidget {
  const MfPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.height = 38,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool enabled;
  final double height;

  @override
  State<MfPrimaryButton> createState() => _FnPrimaryButtonState();
}

class _FnPrimaryButtonState extends State<MfPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final lifted = active && _hovered;
    final pressed = active && _pressed;
    final radius = BorderRadius.circular(10);

    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: active ? (_) => setState(() => _pressed = true) : null,
        onTapUp: active ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: active ? () => setState(() => _pressed = false) : null,
        onTap: active ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          height: widget.height,
          padding: EdgeInsets.symmetric(horizontal: widget.height * 0.46),
          transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: !active
                  ? const [Mf.raised, Mf.raised]
                  : pressed
                  ? const [Color(0xFFD9502F), Mf.accent]
                  : lifted
                  ? const [Color(0xFFFA8362), Mf.accentHover]
                  : const [Mf.accentHover, Mf.accent],
            ),
            boxShadow: !active
                ? null
                : [
                    BoxShadow(
                      color: Color(lifted ? 0x5C2A1009 : 0x3D2A1009),
                      blurRadius: lifted ? 20 : 12,
                      offset: Offset(0, lifted ? 8 : 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon case final icon?) ...[
                Icon(
                  icon,
                  size: widget.height * 0.46,
                  color: active ? Mf.cream : Mf.faint,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: active ? Mf.cream : Mf.faint,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MfIconButton extends StatefulWidget {
  const MfIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 34,
    this.glyph = 18,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double glyph;
  final Color? color;
  final String? tooltip;

  @override
  State<MfIconButton> createState() => _FnIconButtonState();
}

class _FnIconButtonState extends State<MfIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? Mf.textSoft;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered ? Mf.raised : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: widget.glyph,
            color: _hovered ? Mf.text : tint,
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

/// A hairline slider. Material's Slider is a touch control (4dp groove, 20dp
/// thumb); on a desktop window that reads as a fat pill.
class MfScrubber extends StatefulWidget {
  const MfScrubber({
    super.key,
    required this.fraction,
    this.onScrub,
    this.onCommit,
    this.enabled = true,
    this.thumbColor = Mf.accent,
    this.activeColor = Mf.accent,
  });

  final double fraction;
  final ValueChanged<double>? onScrub;
  final VoidCallback? onCommit;
  final bool enabled;
  final Color thumbColor;
  final Color activeColor;

  @override
  State<MfScrubber> createState() => _FnScrubberState();
}

class _FnScrubberState extends State<MfScrubber> {
  double? _dragFraction;
  bool _hovered = false;

  double get _value => (_dragFraction ?? widget.fraction).clamp(0.0, 1.0);

  void _update(double dx, double width) {
    if (!widget.enabled) return;
    final value = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragFraction = value);
    widget.onScrub?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              _update(details.localPosition.dx, width);
              widget.onCommit?.call();
            },
            onHorizontalDragStart: (details) =>
                _update(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _update(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) {
              setState(() => _dragFraction = null);
              widget.onCommit?.call();
            },
            child: SizedBox(
              height: 18,
              child: CustomPaint(
                painter: _ScrubberPainter(
                  fraction: _value,
                  enabled: widget.enabled,
                  hovered: _hovered,
                  thumbColor: widget.thumbColor,
                  activeColor: widget.activeColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScrubberPainter extends CustomPainter {
  _ScrubberPainter({
    required this.fraction,
    required this.enabled,
    required this.hovered,
    required this.thumbColor,
    required this.activeColor,
  });

  /// 2dp groove and a 4dp handle at rest, both grown by a hair on hover.
  static const _baseRadius = 4.0;

  final double fraction;
  final bool enabled;
  final bool hovered;
  final Color thumbColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final grooveHeight = hovered ? 3.0 : 2.0;
    final radius = hovered ? _baseRadius + 1.5 : _baseRadius;
    final inset = radius + 1;
    final left = inset;
    final right = size.width - inset;
    final width = (right - left).clamp(0.0, double.infinity);
    final head = left + width * fraction;

    final groove = Paint()
      ..color = Mf.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = grooveHeight
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), groove);

    if (width > 0 && fraction > 0) {
      final filled = Paint()
        ..color = enabled ? activeColor : Mf.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = grooveHeight
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(left, centerY), Offset(head, centerY), filled);
    }

    // An idle bar keeps the groove only: a handle parked at zero reads as a
    // control you can drag when you cannot.
    if (enabled) {
      canvas.drawCircle(
        Offset(head, centerY),
        radius,
        Paint()..color = thumbColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.fraction != fraction ||
      old.enabled != enabled ||
      old.hovered != hovered ||
      old.thumbColor != thumbColor ||
      old.activeColor != activeColor;
}
