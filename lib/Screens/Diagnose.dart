import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // for MediaType
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class VideoRecorderPage extends StatefulWidget {
  const VideoRecorderPage({super.key});

  @override
  State<VideoRecorderPage> createState() => _VideoRecorderPageState();
}

class _VideoRecorderPageState extends State<VideoRecorderPage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _savingToGallery = true; // toggle if you want
  String? _lastSavedPath;
  YoutubePlayerController _youtubePlayerController =
      new YoutubePlayerController(
          initialVideoId:
              YoutubePlayer.convertUrlToId('https://youtu.be/D5iM8UerZJY')!);
  Future<void> uploadVideoToFastAPI(String filePath) async {
    try {
      var uri = Uri.parse("http://10.160.59.52:8000/upload-video");
      // For emulator, use 10.0.2.2 instead of 127.0.0.1
      // For real device, use your PC's local IP address
      print(
          "---------------------📹 Uploading video to FastAPI: $filePath--------------------------");
      var request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // must match your FastAPI parameter name
          filePath,
          contentType: MediaType('video', 'mp4'), // optional
        ),
      );
      print(
          "---------------📂 File added to request: $filePath ---------------------------");
      var response = await request.send();
      print("++++++++++++++++++ File sent: $filePath ++++++++++++++++");
      if (response.statusCode == 200) {
        var respStr = await response.stream.bytesToString();
        _showSnack("✅ Upload successful");
      } else {
        _showSnack("❌ Upload failed: ${response.statusCode}");
      }
    } catch (e) {
      _showSnack("⚠️ Error uploading video: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _playVideo() {
    const videoUrl = 'https://youtu.be/D5iM8UerZJY';
    _youtubePlayerController = YoutubePlayerController(
      initialVideoId: YoutubePlayer.convertUrlToId(videoUrl)!,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
      ),
    );
  }

  Future<void> _init() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Ask permissions up front
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();

    if (!cam.isGranted || !mic.isGranted) {
      if (mounted) {
        _showSnack('Camera/Microphone permission denied.');
      }
      return;
    }

    _cameras = await availableCameras();

    // Pick a back camera if available, else first camera
    final CameraDescription camera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first);

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _showSnack('Camera init error: ${e.code}');
    }
  }

  // Future<void> _switchCamera() async {
  //   if (_controller == null || _cameras.length < 2 || _isRecording) return;

  //   final current = _controller!.description;
  //   final isBack = current.lensDirection == CameraLensDirection.back;
  //   final next = _cameras.firstWhere(
  //     (c) =>
  //         c.lensDirection ==
  //         (isBack ? CameraLensDirection.back : CameraLensDirection.front),
  //     orElse: () => _cameras.first,
  //   );

  //   await _controller!.dispose();
  //   _controller =
  //       CameraController(next, ResolutionPreset.high, enableAudio: true);
  //   try {
  //     await _controller!.initialize();
  //     if (mounted) setState(() {});
  //   } on CameraException catch (e) {
  //     _showSnack('Switch camera error: ${e.code}');
  //   }
  // }

  Future<void> _startRecording() async {
    if (_controller == null || _isRecording) return;
    try {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    } on CameraException catch (e) {
      _showSnack('Start recording error: ${e.code}');
    }
  }

  Future<void> _stopRecordingAndSave() async {
    if (_controller == null || !_isRecording) return;
    try {
      final XFile xfile = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);

      // Save to app documents directory
      final Directory docsDir = await getApplicationDocumentsDirectory();
      final String fileName =
          'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final String targetPath = p.join(docsDir.path, fileName);
      await xfile.saveTo(targetPath);

      _lastSavedPath = targetPath;
      await uploadVideoToFastAPI(targetPath);
      _showSnack('Video saved to:\n$targetPath');
      _showSnack('Saved to app storage:\n$targetPath');

      if (mounted) setState(() {});
    } on CameraException catch (e) {
      _showSnack('Stop/save error: ${e.code}');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : (!controller.value.isInitialized)
              ? const Center(child: Text('Initializing camera...'))
              : Stack(
                  children: [
                    Center(child: CameraPreview(controller)),
                    Center(
                      child: YoutubePlayer(
                        controller: _youtubePlayerController,
                        showVideoProgressIndicator: true,
                      ),
                    ),
                    if (_isRecording)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Row(
                          children: const [
                            Icon(Icons.fiber_manual_record, color: Colors.red),
                            SizedBox(width: 8),
                            Text('REC', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton.extended(
            heroTag: 'record',
            onPressed: _isRecording ? _stopRecordingAndSave : _startRecording,
            label: Text(_isRecording ? 'Stop & Save' : 'Record'),
            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
          ),
        ],
      ),
    );
  }
}
