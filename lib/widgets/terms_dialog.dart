import 'package:flutter/material.dart';

/// Shows the dedicated Slim4K Terms of Service & Studio License Agreement dialog.
void showSlim4KTermsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const Slim4KTermsDialog(),
  );
}

class Slim4KTermsDialog extends StatelessWidget {
  const Slim4KTermsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F141C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Color(0xFF00E5FF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slim4K Studio Terms & License Agreement',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'NeerTech Technologies • Studio Cinematography & Video Archival Policy',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF21262D), height: 1),
              const SizedBox(height: 14),

              // Scrollable Terms Content
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0F17),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF21262D)),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionBadge('LEGAL AGREEMENT FOR STUDIOS & CINEMATOGRAPHERS'),
                          const SizedBox(height: 10),
                          const Text(
                            'By installing, downloading, authenticating, or running Slim4K, you agree to be bound by the following Terms & Conditions and Studio End-User License Agreement (EULA) operated by NeerTech Technologies ("Company").',
                            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                          ),
                          const SizedBox(height: 16),

                          _buildTermSection(
                            number: '1',
                            title: '100% Local On-Device Transcoding (Absolute Media Privacy)',
                            hindiSummary: 'आपकी शादी या कमर्शियल वीडियो रिकॉर्डिंग 100% आपके अपने कंप्यूटर (GPU/CPU) पर ही प्रोसेस होती है। कोई भी वीडियो कभी भी किसी सर्वर या इंटरनेट पर अपलोड नहीं होता।',
                            body: 'Slim4K processes all 4K, 1080p, and RAW video footage 100% locally on your computer\'s graphics card (NVIDIA NVENC, Intel QSV, AMD AMF, Apple VideoToolbox) and CPU via local FFmpeg binaries. Zero video frames, audio tracks, or metadata are ever transmitted, uploaded, or stored on NeerTech servers. Your studio footage remains strictly private, offline, and confidential.',
                          ),

                          _buildTermSection(
                            number: '2',
                            title: 'Complimentary 2.0 GB Free Evaluation Quota',
                            hindiSummary: 'हर नए कंप्यूटर को 2.0 GB का फ्री ट्रायल मिलता है ताकि आप वीडियो क्वालिटी, कंप्रेशन स्पीड और अपने ग्राफिक्स कार्ड की अनुकूलता पहले जांच सकें।',
                            body: 'Every newly registered workstation or Google account is granted an upfront 2.0 GB free quota. This trial allows cameramen, editors, and studios to thoroughly test compression speed, visual quality retention, and hardware acceleration on actual studio footage before making any commercial purchase.',
                          ),

                          _buildTermSection(
                            number: '3',
                            title: 'Commercial Studio License (10.0 TB Annual Quota)',
                            hindiSummary: 'कमर्शियल लाइसेंस में 365 दिनों के लिए 10 TB का विशाल कोटा मिलता है। यह एक समय में 1 सक्रिय वर्कस्टेशन सीट पर उपयोग के लिए अधिकृत है।',
                            body: 'The Slim4K Commercial Studio License unlocks a 10.0 TB processing quota valid for 365 days from the activation date. Each commercial license grants access for 1 active workstation seat per Google account. Users may transfer their active seat between studio PCs, but concurrent multi-seat usage requires additional seats.',
                          ),

                          _buildTermSection(
                            number: '4',
                            title: 'No-Refund Policy for Activated Digital Goods',
                            hindiSummary: 'चूंकि 2.0 GB का पूरा फ्री ट्रायल सॉफ्टवेयर और क्वालिटी की जांच हेतु पहले ही दिया जाता है, इसलिए भुगतान व लाइसेंस एक्टिवेशन के बाद कोई रिफंड देय नहीं होगा।',
                            body: 'Because Slim4K provides an unrestricted 2.0 GB free evaluation trial for full testing of software capabilities, GPU speeds, and output quality prior to purchase, all commercial license purchases (via UPI, Card, NetBanking, or QR) are strictly non-refundable and non-cancellable once activated or generated.',
                          ),

                          _buildTermSection(
                            number: '5',
                            title: 'Original Footage & Master Backup Responsibility',
                            hindiSummary: 'ओरिजिनल कैमरा फुटेज (SD कार्ड / मास्टर ड्राइव) का बैकअप सुरक्षित रखना हमेशा ग्राहक/स्टूडियो की अपनी जिम्मेदारी है।',
                            body: 'Users are strictly responsible for maintaining independent master backups of all source camera files on original SD cards, external hard drives, or NAS storage. Slim4K generates separate "_slim" video outputs by default and does not delete original camera media. NeerTech Technologies bears zero liability for data loss arising from power cuts, bad sectors, faulty external drives, or OS failures during rendering.',
                          ),

                          _buildTermSection(
                            number: '6',
                            title: 'Hardware Acceleration & Render Performance',
                            hindiSummary: 'रेंडरिंग की गति आपके कंप्यूटर के ग्राफिक्स कार्ड (NVIDIA/Intel/AMD/Apple) और हार्डवेयर ड्राइव की गति पर निर्भर करती है।',
                            body: 'Transcoding throughput depends entirely on the host workstation\'s GPU encoder capability, driver updates, drive read/write speed, and CPU architecture. NeerTech Technologies optimizes the transcoding engine for maximum performance but does not guarantee identical render speeds across differing hardware configurations.',
                          ),

                          _buildTermSection(
                            number: '7',
                            title: 'Intellectual Property & Media Ownership',
                            hindiSummary: 'आपके वीडियो पर 100% कॉपीराइट और मालिकाना हक आपका ही रहता है। सॉफ्टवेयर के कोड या एल्गोरिदम को रिवर्स-इंजीनियर करना वर्जित है।',
                            body: 'The user retains 100% unencumbered copyright, distribution rights, and ownership over all input and output video files. Slim4K software, proprietary UI, compression algorithms, and licensing mechanisms are the exclusive intellectual property of NeerTech Technologies. Reverse engineering, decompiling, or unauthorized bypass of quotas is strictly prohibited.',
                          ),

                          _buildTermSection(
                            number: '8',
                            title: 'Limitation of Liability',
                            hindiSummary: 'हार्डवेयर ख़राबी या सिस्टम क्रैश से किसी भी व्यवसायिक नुकसान या क्लाइंट डिलीवरी में देरी के लिए कंपनी उत्तरदायी नहीं होगी।',
                            body: 'In no event shall NeerTech Technologies, its directors, or developers be liable for any indirect, consequential, or punitive damages, lost business profits, or client wedding delivery disputes arising out of the use or inability to use the software.',
                          ),

                          _buildTermSection(
                            number: '9',
                            title: 'Governing Law & Jurisdiction',
                            hindiSummary: 'यह समझौता भारत सरकार के सूचना प्रौद्योगिकी अधिनियम और भारतीय अनुबंध अधिनियम 1872 के तहत प्रयागराज (इलाहाबाद) न्यायालय के क्षेत्राधिकार में आता है।',
                            body: 'This agreement is governed by the laws of India, including the Information Technology Act 2000 and the Indian Contract Act 1872. All legal disputes shall be subject to the exclusive jurisdiction of the competent courts in Prayagraj (Allahabad), Uttar Pradesh, India.',
                          ),

                          _buildTermSection(
                            number: '10',
                            title: 'Official Studio Support & Helpdesk',
                            hindiSummary: 'किसी भी तकनीकी सहायता या लाइसेंस ट्रांसफर के लिए संपर्क करें: techsupport@neertechtechnologies.in | +91 74588 29500',
                            body: 'For license migration, workstation seat transfers, or hardware troubleshooting, contact NeerTech Technologies Helpdesk:\n• Email: techsupport@neertechtechnologies.in\n• Support Helpline & WhatsApp: +91 74588 29500\n• Web Portal: https://neertechtechnologies.in/supports-slim4k.html',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Version 1.0.1 • Updated March 2026',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: const Color(0xFF0D1117),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('I Understand & Agree', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTermSection({
    required String number,
    required String title,
    required String hindiSummary,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFC9D1D9),
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(6),
              border: const Border(left: BorderSide(color: Color(0xFF00E676), width: 2.5)),
            ),
            child: Text(
              'हिन्दी: $hindiSummary',
              style: const TextStyle(
                color: Color(0xFFA7F3D0),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
