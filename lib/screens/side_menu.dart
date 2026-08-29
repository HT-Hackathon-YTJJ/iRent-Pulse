import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'credit_score_screen.dart';

/// 左側選單 (Figma: 信用點數 → 有左側選單的首頁 → 左側選單).
///
/// The redesign moves every entry onto its own white card over a grey ground —
/// the old version was a flat bullet list — and puts the two membership
/// numbers the user actually opens the drawer for (信用分數 / 獎勵金) straight
/// into the dark header as taps into 信用分數與會員權益.
class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  static const _entries = <_MenuEntry>[
    _MenuEntry(Icons.account_balance_wallet_outlined, '和雲錢包', '開通錢包・立即儲值'),
    _MenuEntry(Icons.credit_card_outlined, '支付設定', '支付方式・發票載具'),
    _MenuEntry(Icons.assignment_outlined, '歷史訂單', '查看里程與過往訂單'),
    _MenuEntry(Icons.card_giftcard, '優惠管理', '兌換碼・剩餘時數・折價券'),
    _MenuEntry(Icons.push_pin_outlined, '訂閱管理', 'PRO 會員・訂閱制 +'),
  ];

  void _openCredit(BuildContext context) {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute(builder: (_) => const CreditScoreScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColor.divider,
      width: MediaQuery.sizeOf(context).width * 0.80,
      shape: const RoundedRectangleBorder(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(onOpenCredit: () => _openCredit(context)),
          _ProBar(onTap: () => _openCredit(context)),
          const SizedBox(height: 14),
          for (final entry in _entries) ...[
            _MenuCard(entry: entry),
            const SizedBox(height: 15),
          ],
          const SizedBox(height: 9),
          const _FooterLinks(),
          const SizedBox(height: 22),
          const _RewardBanner(),
          const SizedBox(height: 10),
          const _ReferralBanner(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenCredit});

  final VoidCallback onOpenCredit;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColor.sheetDark,
      padding: EdgeInsets.fromLTRB(
        18,
        MediaQuery.paddingOf(context).top + 22,
        18,
        26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Hi, 林O明',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {},
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: '通知',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  label: '信用分數',
                  value: '117',
                  color: AppColor.brand,
                  onTap: onOpenCredit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatPill(
                  label: '獎勵金',
                  value: r'$15',
                  color: AppColor.warning,
                  onTap: onOpenCredit,
                ),
              ),
              IconButton(
                onPressed: onOpenCredit,
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: '信用分數與會員權益',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // Two pills share the drawer width, so on a narrow display there is
          // no room for "信用分數 | 117" at its designed size. Scaling the whole
          // pill down keeps the label readable; clipping it left "信…｜117".
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Container(
                  width: 1,
                  height: 15,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: Colors.white54,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The white "成為 PRO 會員" strip. In Figma it straddles the header edge, so
/// it is pulled up over the boundary here too.
class _ProBar extends StatelessWidget {
  const _ProBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 21),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          elevation: 2,
          shadowColor: const Color(0x40000000),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.brand,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColor.brandSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '成為 PRO 會員',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColor.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColor.textPlaceholder,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuEntry {
  const _MenuEntry(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.entry});

  final _MenuEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      // The shadow hangs outside the Material rather than being an Ink
      // decoration inside it: a Material clips its ink features to its own
      // rectangle, which squared the blur off and left a dark notch in each
      // rounded corner.
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          boxShadow: AppShadow.card,
        ),
        child: Material(
          color: AppColor.card,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
              child: Row(
                children: [
                  Icon(entry.icon, size: 30, color: AppColor.textPrimary),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: AppColor.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColor.textPlaceholder,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColor.textPlaceholder,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  const _RewardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDE4EA), Color(0xFFFBD3DE)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF06292),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(
              Icons.directions_car,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '時時回饋計劃',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD5305C),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8365E),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              '點我換好禮！',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferralBanner extends StatelessWidget {
  const _ReferralBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3DC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        children: [
          Icon(Icons.card_giftcard, color: Color(0xFFF5A623), size: 24),
          SizedBox(width: 10),
          Text(
            '推薦好友領折抵券',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFCF8A1B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '關於 iRent',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColor.textPrimary,
          ),
        ),
        SizedBox(width: 50),
        Text(
          '|',
          style: TextStyle(fontSize: 14, color: AppColor.textPlaceholder),
        ),
        SizedBox(width: 50),
        Text(
          '聯絡我們',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColor.textPrimary,
          ),
        ),
      ],
    );
  }
}
