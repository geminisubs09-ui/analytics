import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/sales_provider.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _isUploadingSales = false;
  bool _isUploadingProducts = false;
  String _uploadStatus = '';

  Future<void> _pickAndUploadSales(BuildContext context) async {
    setState(() {
      _isUploadingSales = true;
      _uploadStatus = 'Selecting sales daybook...';
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isUploadingSales = false;
          _uploadStatus = 'No file selected.';
        });
        return;
      }

      final file = result.files.first;
      setState(() {
        _uploadStatus = 'Uploading ${file.name}...';
      });

      List<int>? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = file.bytes ?? await io.File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Could not read file contents.');
      }

      final response = await context.read<SalesProvider>().uploadSalesSheet(bytes, file.name);

      _showResultDialog(
        title: 'Sales Sync Completed',
        content: 'Total Parsed Vouchers: ${response['total_parsed_vouchers']}\n'
            'New Vouchers Imported: ${response['new_vouchers_imported']}\n'
            'New Items Imported: ${response['new_items_imported']}\n'
            'Duplicates Skipped: ${response['skipped_duplicate_vouchers']}',
        isSuccess: true,
      );

      setState(() {
        _uploadStatus = 'Sales register uploaded successfully!';
      });
    } catch (e) {
      _showResultDialog(
        title: 'Upload Failed',
        content: e.toString(),
        isSuccess: false,
      );
      setState(() {
        _uploadStatus = 'Error occurred during upload.';
      });
    } finally {
      setState(() {
        _isUploadingSales = false;
      });
    }
  }

  Future<void> _pickAndUploadProducts(BuildContext context) async {
    setState(() {
      _isUploadingProducts = true;
      _uploadStatus = 'Selecting product groups map...';
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isUploadingProducts = false;
          _uploadStatus = 'No file selected.';
        });
        return;
      }

      final file = result.files.first;
      setState(() {
        _uploadStatus = 'Uploading ${file.name}...';
      });

      List<int>? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = file.bytes ?? await io.File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('Could not read file contents.');
      }

      final response = await context.read<SalesProvider>().uploadProductsSheet(bytes, file.name);

      _showResultDialog(
        title: 'Products Sync Completed',
        content: 'Successfully synced product classifications.\n'
            'Total mapped products uploaded: ${response['total_products_synced']}',
        isSuccess: true,
      );

      setState(() {
        _uploadStatus = 'Product categories synced successfully!';
      });
    } catch (e) {
      _showResultDialog(
        title: 'Upload Failed',
        content: e.toString(),
        isSuccess: false,
      );
      setState(() {
        _uploadStatus = 'Error occurred during upload.';
      });
    } finally {
      setState(() {
        _isUploadingProducts = false;
      });
    }
  }

  void _showResultDialog({required String title, required String content, required bool isSuccess}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? const Color(0xFF10B981) : Colors.red,
            ),
            const SizedBox(width: 12),
            Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(content, style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.outfit(color: const Color(0xFF6366F1))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          'Excel Data Upload',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  color: const Color(0xFF6366F1).withOpacity(0.8),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Upload Excel Spreadsheets',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select Excel (.xlsx) reports exported from your ledger systems to parse and sync into the database.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // Upload Sales Card
                _buildUploadOption(
                  title: 'Upload Sales Daybook',
                  description: 'Contains sales voucher headers and transaction line items.',
                  isLoading: _isUploadingSales,
                  isDisabled: _isUploadingProducts,
                  icon: Icons.receipt_long,
                  color: const Color(0xFF6366F1),
                  onPressed: () => _pickAndUploadSales(context),
                ),
                const SizedBox(height: 20),

                // Upload Products Card
                _buildUploadOption(
                  title: 'Upload Product Category Map',
                  description: 'Contains product name maps to group categorizations.',
                  isLoading: _isUploadingProducts,
                  isDisabled: _isUploadingSales,
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFF10B981),
                  onPressed: () => _pickAndUploadProducts(context),
                ),

                if (_uploadStatus.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.02)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _uploadStatus,
                            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadOption({
    required String title,
    required String description,
    required bool isLoading,
    required bool isDisabled,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.outfit(color: Colors.white30, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: (isLoading || isDisabled) ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: Colors.white12,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
