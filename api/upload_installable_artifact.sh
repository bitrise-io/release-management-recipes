import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';

void main() => runApp(const VideoSleuthApp());

class VideoSleuthApp extends StatelessWidget {
  const VideoSleuthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Sleuth',
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  File? _video;
  String _log = '';
  List<FileSystemEntity> _outputs = [];

  Future<void> pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    setState(() {
      _video = File(res.files.single.path!);
      _log = '';
      _outputs = [];
    });
  }

  Future<void> analyze() async {
    final video = _video;
    if (video == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/sleuth_out');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);

    // 1) Sample frames (1 frame every 0.5 seconds = 2 fps)
    // You can tune fps=2, fps=1, etc.
    final framesPattern = '${outDir.path}/frame_%05d.jpg';
    final cmdFrames =
        '-y -i "${video.path}" -vf fps=2 -q:v 3 "$framesPattern"';
    await FFmpegKit.execute(cmdFrames);

    // 2) Spectrogram image
    final spectro = '${outDir.path}/spectrogram.png';
    final cmdSpec =
        '-y -i "${video.path}" -lavfi showspectrumpic=s=1024x256:legend=1 "$spectro"';
    await FFmpegKit.execute(cmdSpec);

    // Refresh output list
    final outputs = outDir.listSync();
    setState(() {
      _outputs = outputs;
      _log = 'Done.\nFrames + spectrogram saved to:\n${outDir.path}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Sleuth 🕵️📼')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: pickVideo,
              child: const Text('Pick a video'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _video == null ? null : analyze,
              child: const Text('Analyze'),
            ),
            const SizedBox(height: 16),
            if (_video != null) Text('Video: ${_video!.path}'),
            const SizedBox(height: 12),
            Text(_log),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _outputs.length,
                itemBuilder: (context, i) {
                  final f = _outputs[i];
                  return ListTile(
                    title: Text(f.path.split('/').last),
                    subtitle: Text(f.path),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
