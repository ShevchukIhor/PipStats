import 'package:flutter/material.dart';
import 'package:pipstats/tip_service.dart';
import 'package:pipstats/l10n/app_localizations.dart';
import 'package:pipstats/theme.dart';

class TipWidget extends StatefulWidget {
  final String walletAddress;
  final TipToken type;

  const TipWidget({super.key, required this.walletAddress, this.type = TipToken.skr});

  @override
  State<TipWidget> createState() => _TipWidgetState();
}

class _TipWidgetState extends State<TipWidget> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _isSending = false;
  late TipToken _selectedType;

  /// Minimum for the currently selected token, e.g. "MIN: 5 SKR".
  String get _minLimitMessage => _selectedType == TipToken.sol
      ? 'MIN: ${TipService.minSolDisplay} SOL'
      : 'MIN: ${TipService.minSkrDisplay} SKR';

  String get _defaultAmount => _selectedType == TipToken.sol
      ? TipService.minSolDisplay
      : TipService.minSkrDisplay;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.type;
    _amountController.text = _defaultAmount;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _handleTip() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final signature = await TipService.instance.sendTipFlow(
        ownerAddress: widget.walletAddress,
        amountText: _amountController.text,
        type: _selectedType,
      );

      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final ds = context.ds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tipSuccess(signature),
            style: TextStyle(color: ds.bg),
          ),
          backgroundColor: ds.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      String errorMessage = l10n.tipError(e.toString());
      final errorStr = e.toString();

      if (errorStr.contains('MIN_LIMIT_SOL') ||
          errorStr.contains('MIN_LIMIT_SKR')) {
        errorMessage = _minLimitMessage;
      } else if (errorStr.contains('INVALID_AMOUNT')) {
        errorMessage = l10n.tipInvalidAmount;
      } else if (errorStr.contains('NO_SKR_ACCOUNT')) {
        errorMessage = l10n.tipNoSkrAccount;
      } else if (errorStr.contains('TIP_CANCELLED') ||
          errorStr.contains('NO_SIGNATURE_RETURNED')) {
        errorMessage = l10n.tipCancelled;
      } else if (errorStr.contains('AUTH_REQUIRED')) {
        errorMessage = l10n.tipAuthRequired;
      } else if (errorStr.contains('IDENTITY_MISMATCH')) {
        errorMessage = l10n.tipIdentityMismatch;
      } else if (errorStr.contains('INSUFFICIENT_SOL')) {
        errorMessage = l10n.tipInsufficientSol;
      } else if (errorStr.contains('INSUFFICIENT_SKR')) {
        errorMessage = l10n.tipInsufficientSkr;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            style: TextStyle(color: context.ds.bg),
          ),
          backgroundColor: context.ds.dangerTextStrong,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ds = context.ds;

    return AlertDialog(
      backgroundColor: ds.panel,
      title: Text(
        l10n.tipTitle,
        style: TextStyle(color: ds.primary, fontSize: PipText.heading),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TipToken>(
              style: SegmentedButton.styleFrom(
                // The default segment height is well under the 48dp touch
                // minimum once the type scale goes up.
                minimumSize: const Size(0, 52),
              ),
              segments: [
                ButtonSegment(
                  value: TipToken.sol,
                  label: Text('SOL', style: TextStyle(fontSize: PipText.title)),
                ),
                ButtonSegment(
                  value: TipToken.skr,
                  label: Text('SKR', style: TextStyle(fontSize: PipText.title)),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (Set<TipToken> newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                  _amountController.text = _defaultAmount;
                });
              },
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: l10n.tipAmountHint,
                hintStyle: TextStyle(color: ds.dim, fontSize: PipText.title),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                errorStyle: TextStyle(fontSize: PipText.note),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: ds.primary),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: ds.primary, width: 2),
                ),
              ),
              style: TextStyle(color: ds.primary, fontSize: PipText.hero),
              validator: (v) {
                // Same conversion the send path uses, so what validates here
                // is exactly what gets submitted.
                final raw = TipService.parseAmountToBaseUnits(
                  v ?? '',
                  _selectedType == TipToken.sol
                      ? TipService.solDecimals
                      : TipService.skrDecimals,
                );
                if (raw == null) return l10n.tipInvalidAmount;
                if (_selectedType == TipToken.sol &&
                    raw < TipService.minSolLamports) {
                  return _minLimitMessage;
                }
                if (_selectedType == TipToken.skr &&
                    raw < TipService.minSkrBaseUnits) {
                  return _minLimitMessage;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(88, 48)),
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: Text(
            l10n.cancel,
            style: TextStyle(color: ds.dim, fontSize: PipText.title),
          ),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _handleTip,
          style: ElevatedButton.styleFrom(
            backgroundColor: ds.primary,
            minimumSize: const Size(96, 48),
          ),
          child: _isSending
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ds.bg,
                  ),
                )
              : Text(
                  l10n.tipSend,
                  style: TextStyle(color: ds.bg, fontSize: PipText.title),
                ),
        ),
      ],
    );
  }
}

