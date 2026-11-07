/// Inputs and controls tuned for a pointer-driven desktop window: 38dp fields,
/// a 34dp search pill and hairline sliders instead of Material's 56dp forms and
/// 20dp-thumb sliders.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

class FnField extends StatefulWidget {
  const FnField({
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
  State<FnField> createState() => _FnFieldState();
}

class _FnFieldState extends State<FnField> {
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
  void didUpdateWidget(covariant FnField oldWidget) {
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
            color: _focused ? Fn.accent : Fn.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Fn.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Fn.accent : Fn.border,
            ),
          ),
          child: Center(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              obscureText: widget.password,
              onSubmitted: (_) => widget.onSubmit?.call(),
              cursorColor: Fn.accent,
              cursorWidth: 1.4,
              style: const TextStyle(fontSize: 13, color: Fn.text),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: const TextStyle(color: Fn.faint, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FnSearchField extends StatefulWidget {
  const FnSearchField({
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
  State<FnSearchField> createState() => _FnSearchFieldState();
}

class _FnSearchFieldState extends State<FnSearchField> {
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
  void didUpdateWidget(covariant FnSearchField oldWidget) {
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
        ? Fn.accent
        : (_hovered ? Fn.muted : Fn.border);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 3),
        decoration: BoxDecoration(
          color: Fn.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 15,
              color: _focused ? Fn.muted : Fn.faint,
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
                  cursorColor: Fn.accent,
                  cursorWidth: 1.4,
                  style: const TextStyle(fontSize: 12.5, color: Fn.text),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: const TextStyle(
                      color: Fn.faint,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.value.isNotEmpty && widget.onClear != null)
              FnIconButton(
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

class FnPrimaryButton extends StatefulWidget {
  const FnPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.height = 40,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;

  @override
  State<FnPrimaryButton> createState() => _FnPrimaryButtonState();
}

class _FnPrimaryButtonState extends State<FnPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final color = !active
        ? Fn.raised
        : (_hovered ? Fn.accentHover : Fn.accent);
    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: active ? widget.onTap : null,
        child: Container(
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: active ? Fn.cream : Fn.faint,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class FnIconButton extends StatefulWidget {
  const FnIconButton({
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
  State<FnIconButton> createState() => _FnIconButtonState();
}

class _FnIconButtonState extends State<FnIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? Fn.textSoft;
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
            color: _hovered ? Fn.raised : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: widget.glyph,
            color: _hovered ? Fn.text : tint,
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
class FnScrubber extends StatefulWidget {
  const FnScrubber({
    super.key,
    required this.fraction,
    this.onScrub,
    this.onCommit,
    this.enabled = true,
    this.thumbColor = Fn.accent,
    this.activeColor = Fn.accent,
  });

  final double fraction;
  final ValueChanged<double>? onScrub;
  final VoidCallback? onCommit;
  final bool enabled;
  final Color thumbColor;
  final Color activeColor;

  @override
  State<FnScrubber> createState() => _FnScrubberState();
}

class _FnScrubberState extends State<FnScrubber> {
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
      ..color = Fn.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = grooveHeight
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(left, centerY), Offset(right, centerY), groove);

    if (width > 0 && fraction > 0) {
      final filled = Paint()
        ..color = enabled ? activeColor : Fn.border
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
