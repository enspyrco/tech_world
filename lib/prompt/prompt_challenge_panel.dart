import 'package:flutter/material.dart';
import 'package:tech_world/editor/challenge.dart';
import 'package:tech_world/prompt/cast_result.dart';
import 'package:tech_world/prompt/prompt_challenge.dart';
import 'package:tech_world/prompt/spell_school.dart';
import 'package:tech_world/prompt/spell_slot_service.dart';
import 'package:tech_world/spellbook/word_of_power.dart' show arcaneColor;

/// Panel for crafting and casting prompt spells.
///
/// Replaces the code editor panel when a player interacts with a
/// prompt-mode terminal. Shows the challenge, spell slot orbs,
/// a text input for the prompt, and cast results.
class PromptChallengePanel extends StatefulWidget {
  const PromptChallengePanel({
    required this.challenge,
    required this.spellSlotService,
    required this.onCast,
    required this.onClose,
    super.key,
  });

  final PromptChallenge challenge;
  final SpellSlotService spellSlotService;

  /// Called when the player casts a spell. Returns the agent's response
  /// and the evaluation result.
  final Future<(String response, CastResult result)> Function(String prompt)
      onCast;

  final VoidCallback onClose;

  @override
  State<PromptChallengePanel> createState() => _PromptChallengePanelState();
}

class _PromptChallengePanelState extends State<PromptChallengePanel> {
  final _promptController = TextEditingController();
  bool _isCasting = false;
  String? _agentResponse;
  CastResult? _lastResult;

  static const _successColor = Color(0xFF44AA44);
  static const _failColor = Color(0xFFDD4444);

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _onCast() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    if (!widget.spellSlotService.canCast) return;

    setState(() {
      _isCasting = true;
      _lastResult = null;
      _agentResponse = null;
    });

    // Consume slot before casting.
    widget.spellSlotService.consumeSlot();

    try {
      final (response, result) = await widget.onCast(prompt);
      if (!mounted) return;
      setState(() {
        _isCasting = false;
        _agentResponse = response;
        _lastResult = result;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCasting = false;
        _lastResult = const CastResult(
          passed: false,
          feedback: CastFeedback.unclear,
          judgeReasoning: 'Something went wrong. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E2E),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF333355)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildChallengeInfo(),
                const SizedBox(height: 16),
                _buildSpellSlots(),
                const SizedBox(height: 16),
                _buildPromptInput(),
                const SizedBox(height: 12),
                _buildCastButton(),
                if (_lastResult != null) ...[
                  const SizedBox(height: 16),
                  _buildResult(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF15152A),
      child: Row(
        children: [
          _schoolBadge(widget.challenge.school),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.challenge.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _difficultyChip(widget.challenge.difficulty),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeInfo() {
    return Text(
      widget.challenge.description,
      style: const TextStyle(
        color: Color(0xFFCCCCDD),
        fontSize: 14,
        height: 1.5,
      ),
    );
  }

  Widget _buildSpellSlots() {
    return ListenableBuilder(
      listenable: widget.spellSlotService,
      builder: (context, _) {
        final available = widget.spellSlotService.availableSlots;
        final max = widget.spellSlotService.maxSlots;
        return Row(
          children: [
            const Text(
              'Spell Slots',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            for (var i = 0; i < max; i++) ...[
              _slotOrb(i < available),
              if (i < max - 1) const SizedBox(width: 4),
            ],
            if (!widget.spellSlotService.canCast) ...[
              const SizedBox(width: 8),
              Text(
                'Regenerating...',
                style: TextStyle(
                  color: arcaneColor.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _slotOrb(bool filled) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? arcaneColor : const Color(0xFF333355),
        border: Border.all(
          color: filled ? arcaneColor : const Color(0xFF555577),
          width: 1.5,
        ),
        boxShadow: filled
            ? [BoxShadow(color: arcaneColor.withValues(alpha: 0.4), blurRadius: 6)]
            : null,
      ),
    );
  }

  Widget _buildPromptInput() {
    return TextField(
      controller: _promptController,
      maxLines: 6,
      minLines: 3,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: 'Craft your incantation...',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: const Color(0xFF12121F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: arcaneColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: arcaneColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: arcaneColor),
        ),
      ),
    );
  }

  Widget _buildCastButton() {
    final canCast = widget.spellSlotService.canCast &&
        _promptController.text.trim().isNotEmpty &&
        !_isCasting;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canCast ? _onCast : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: arcaneColor,
          disabledBackgroundColor: const Color(0xFF333355),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isCasting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Cast Spell',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _lastResult!;
    final passed = result.passed;
    final color = passed ? _successColor : _failColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                passed ? Icons.auto_awesome : Icons.close,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _feedbackTitle(result.feedback),
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_agentResponse != null && _agentResponse!.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              "Clawd's response:",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _truncateResponse(_agentResponse!),
              style: const TextStyle(
                color: Color(0xFFCCCCDD),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          if (result.judgeReasoning != null) ...[
            const SizedBox(height: 8),
            Text(
              result.judgeReasoning!,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 12,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _feedbackTitle(CastFeedback feedback) {
    switch (feedback) {
      case CastFeedback.resonates:
        return 'The words of power resonate!';
      case CastFeedback.fizzled:
        return 'The spell fizzled...';
      case CastFeedback.backfired:
        return 'The spell backfired!';
      case CastFeedback.unclear:
        return 'The incantation was unclear.';
    }
  }

  /// Truncate the agent response for display, cutting before RESULT markers.
  String _truncateResponse(String text) {
    final resultIndex = text.toUpperCase().indexOf('RESULT:');
    final display = resultIndex > 0 ? text.substring(0, resultIndex).trim() : text;
    return display.length > 500 ? '${display.substring(0, 500)}...' : display;
  }

  Widget _schoolBadge(SpellSchool school) {
    final (label, icon) = switch (school) {
      SpellSchool.evocation => ('Evocation', Icons.bolt),
      SpellSchool.divination => ('Divination', Icons.visibility),
      SpellSchool.transmutation => ('Transmutation', Icons.transform),
      SpellSchool.illusion => ('Illusion', Icons.theater_comedy),
      SpellSchool.enchantment => ('Enchantment', Icons.psychology),
      SpellSchool.conjuration => ('Conjuration', Icons.auto_fix_high),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: arcaneColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: arcaneColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: arcaneColor, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: arcaneColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _difficultyChip(Difficulty difficulty) {
    final (label, color) = switch (difficulty) {
      Difficulty.beginner => ('Beginner', const Color(0xFF44AA44)),
      Difficulty.intermediate => ('Intermediate', const Color(0xFFDDAA00)),
      Difficulty.advanced => ('Advanced', const Color(0xFFDD4444)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}
