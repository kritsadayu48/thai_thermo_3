import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
// ลบ import ของ dart:html ที่มีปัญหาออก

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  
  const WebViewScreen({
    Key? key, 
    required this.url, 
    required this.title,
  }) : super(key: key);

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _controllerInitialized = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    }
  }
  
  void _initWebView() {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              debugPrint('WebView started loading: $url');
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
              }
            },
            onPageFinished: (String url) {
              debugPrint('WebView finished loading: $url');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              
              // Check for 404 errors by injecting JavaScript
              _controller.runJavaScript(
                'document.title;'
              ).then((dynamic result) {
                String title = result?.toString() ?? '';
                debugPrint('Page title: $title');
                if (title.contains('404')) {
                  debugPrint('Detected 404 page from title');
                  _handle404Error();
                }
              }).catchError((e) {
                debugPrint('Error checking page title: $e');
              });
              
              // Also check the URL for 404 indicators
              if (url.contains('/404') || url.contains('error=404')) {
                debugPrint('Detected 404 from URL: $url');
                _handle404Error();
              }
              _injectUserScripts();
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint('WebView error: Type=${error.errorType}, Code=${error.errorCode}, Description=${error.description}');
              
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  
                  // ให้คำอธิบายที่เข้าใจง่ายขึ้นตามประเภทข้อผิดพลาด
                  if (error.errorCode == 404 || error.description.contains('404')) {
                    _errorMessage = 'ไม่พบหน้าเว็บที่ต้องการ (404 Not Found) - อาจเกิดจากไม่มีข้อมูลแผ่นดินไหวนี้ในระบบ USGS';
                  } else if (error.errorCode == -2 || error.description.toLowerCase().contains('network')) {
                    _errorMessage = 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ - กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต';
                  } else {
                    _errorMessage = 'เกิดข้อผิดพลาด: ${error.description}';
                  }
                });
              }
            },
            onUrlChange: (UrlChange change) {
              debugPrint('WebView URL changed to: ${change.url}');
            },
          ),
        );
      
      // Set user agent to be more like a browser
      _controller.setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1');
      
      debugPrint('Loading URL in WebView: ${widget.url}');
      _controller.loadRequest(Uri.parse(widget.url));
      _controllerInitialized = true;
    } catch (e) {
      debugPrint('Error initializing WebView controller: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'เกิดข้อผิดพลาดในการเปิด WebView: $e';
      });
    }
  }

  // Handle 404 errors specifically
  void _handle404Error() {
    if (mounted && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = 'ไม่พบหน้าเว็บที่ต้องการ (404 Not Found) - อาจเกิดจากไม่มีข้อมูลแผ่นดินไหวนี้ในระบบ USGS';
      });
    }
  }

  void _injectUserScripts() {
    _controller.addJavaScriptChannel(
      'Flutter',
      onMessageReceived: (JavaScriptMessage message) {
        debugPrint('JS message: ${message.message}');
      },
    );
    
    // รอให้หน้าเว็บโหลดเสร็จแล้วทำการคลิกปุ่ม
    _controller.runJavaScript('''
      setTimeout(function() {
        var downloadButton = document.querySelector('.download');
        if (downloadButton) downloadButton.click();
        
        // ตรวจสอบข้อความ "Didn't find what you were looking for?"
        var notFoundText = document.body.innerText.includes("Didn't find what you were looking for?");
        if (notFoundText) {
          window.Flutter.postMessage("404_page_detected");
        }
      }, 2000);
    ''');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (!kIsWeb && !_hasError && _controllerInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _controller.reload();
              },
              tooltip: 'รีเฟรช',
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              _showShareDialog(context);
            },
            tooltip: 'แชร์',
          ),
        ],
      ),
      body: kIsWeb
          ? _buildWebNotSupported()
          : _hasError 
              ? _buildErrorView()
              : _buildWebView(),
    );
  }

  Widget _buildWebView() {
    return Stack(
      children: [
        _controllerInitialized
            ? WebViewWidget(controller: _controller)
            : const Center(
                child: Text("กำลังเตรียมโหลดเว็บไซต์..."),
              ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'ไม่สามารถโหลดเว็บไซต์ได้',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            if (_errorMessage.contains('404'))
              Column(
                children: [
                  const Text(
                    'อาจเกิดจากไม่มีข้อมูลแผ่นดินไหวนี้ในระบบ USGS หรือ URL ไม่ถูกต้อง',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            if (_controllerInitialized)
              ElevatedButton.icon(
                onPressed: () {
                  _controller.reload();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('ลองใหม่'),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                _openLinkInNewTab(widget.url);
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('เปิดในเบราว์เซอร์'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('ย้อนกลับ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebNotSupported() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.open_in_new, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              'สำหรับเว็บ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'เนื่องจากข้อจำกัดของเทคโนโลยี คุณจำเป็นต้องเปิดลิงก์ด้านล่างในแท็บใหม่',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.url,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _copyToClipboard(context, widget.url);
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('คัดลอกลิงก์'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    _openLinkInNewTab(widget.url);
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('เปิดในแท็บใหม่'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLinkInNewTab(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        // Show disclosure dialog
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('เปิดในเบราว์เซอร์'),
            content: const Text('คุณกำลังจะออกจากแอปเพื่อเปิดลิงก์ในเบราว์เซอร์'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('เปิด'),
              ),
            ],
          ),
        );
        
        if (shouldOpen == true) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถเปิดลิงก์ได้: $e')),
        );
      }
    }
  }

  void _showShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('แชร์ลิงค์'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('คัดลอกลิงค์เพื่อแชร์:'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.url,
                        style: const TextStyle(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        _copyToClipboard(context, widget.url);
                        Navigator.pop(context);
                      },
                      tooltip: 'คัดลอกลิงค์',
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('ปิด'),
            ),
            ElevatedButton(
              onPressed: () {
                _copyToClipboard(context, widget.url);
                Navigator.pop(context);
              },
              child: const Text('คัดลอกลิงค์'),
            ),
          ],
        );
      },
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('คัดลอกลิงค์แล้ว')),
      );
    });
  }
} 