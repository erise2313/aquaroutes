import 'package:flutter/material.dart';

/// Shared styled field for the auth screens (login/register), with a
/// built-in show/hide toggle for password fields -- previously every
/// password field was permanently obscured with no way to check what you
/// typed before submitting.
///
/// Colours come from the ambient ColorScheme rather than WebTheme. These
/// screens are pushed from the app as well as the website, and appRoute wraps
/// them in AppTheme -- which registers AppPalette, not WebPalette. WebTheme.of
/// therefore fell back to its *light* palette there, so in the app's dark mode
/// the field was filled pale while the text inherited near-white ink: you
/// could not see what you were typing. Every theme family populates
/// ColorScheme, so reading that works on all three.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.validator,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onSubmitted;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscured,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      autofillHints: widget.autofillHints,
      // Pinned to the scheme's own text colour so it can never inherit an
      // ink that the fill below doesn't suit.
      style: TextStyle(color: scheme.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIcon: Icon(widget.icon, color: scheme.onSurfaceVariant),
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
    );
  }
}
