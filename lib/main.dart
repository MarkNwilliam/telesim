import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TelecoSim',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Telesim'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  final picker = ImagePicker();
  bool _isUploading = false;
  String? _uploadedImageUrl;
  String _connectionStatus = 'Unknown';
  String _networkDetails = 'Fetching...';
  bool _isAnalyzing = false;
  String _analysisResult = '';

  String _reportContent = '';  // New variable to store report content
  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();

  // TextEditingControllers for population, location, and description
  final TextEditingController _populationController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initConnectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> initConnectivity() async {
    try {
      List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      print('Couldn\'t check connectivity status: $e');
      setState(() => _connectionStatus = 'Unknown');
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) async {
    setState(() {
      if (results.contains(ConnectivityResult.mobile)) {
        _connectionStatus = 'Mobile';
      } else if (results.contains(ConnectivityResult.wifi)) {
        _connectionStatus = 'WiFi';
      } else if (results.contains(ConnectivityResult.ethernet)) {
        _connectionStatus = 'Ethernet';
      } else if (results.contains(ConnectivityResult.vpn)) {
        _connectionStatus = 'VPN';
      } else if (results.contains(ConnectivityResult.bluetooth)) {
        _connectionStatus = 'Bluetooth';
      } else if (results.contains(ConnectivityResult.other)) {
        _connectionStatus = 'Other';
      } else {
        _connectionStatus = 'No Internet';
      }
    });

    _updateNetworkDetails();
  }

  Future<void> _updateNetworkDetails() async {
    String details = '';

    try {
      if (_connectionStatus == 'WiFi') {
        details += 'SSID: ${await _networkInfo.getWifiName() ?? 'Unknown'}\n';
        details += 'BSSID: ${await _networkInfo.getWifiBSSID() ?? 'Unknown'}\n';
        details += 'IP: ${await _networkInfo.getWifiIP() ?? 'Unknown'}\n';
      } else if (_connectionStatus == 'Mobile') {
        details += 'Carrier: ${await _getMobileCarrier()}\n';
      }

      details += 'Network Speed: ${await _getNetworkSpeed()}';
    } catch (e) {
      details = 'Error fetching network details: $e';
    }

    setState(() {
      _networkDetails = details;
    });
  }

  Future<String> _getMobileCarrier() async {
    return 'Not available';
  }

  Future<String> _getNetworkSpeed() async {
    return 'Not available';
  }

  Future<void> getImageFromGallery() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    _processPickedFile(pickedFile);
  }

  Future<void> getImageFromCamera() async {
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    _processPickedFile(pickedFile);
  }

  void _processPickedFile(XFile? pickedFile) {
    setState(() {
      if (pickedFile != null) {
        _image = File(pickedFile.path);
        _uploadedImageUrl = null;
      }
    });
  }

  Future<void> uploadImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final String fileName = DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';
      final uri = Uri.parse('http://40.127.8.37:2000/upload');

      var request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('image', _image!.path))
        ..fields['population'] = _populationController.text
        ..fields['location'] = _locationController.text
        ..fields['description'] = _descriptionController.text;

      var response = await request.send();

      if (response.statusCode == 200) {
        var responseBody = await response.stream.bytesToString();
        var jsonResponse = jsonDecode(responseBody);
        String uploadedUrl = jsonResponse['url'];

        setState(() {
          _uploadedImageUrl = uploadedUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded successfully')),
        );
      } else {
        throw Exception('Failed to upload image');
      }
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }


Future<void> analyzeImage() async {
  String description = _descriptionController.text;
  String location = _locationController.text;
  String population = _populationController.text;

  String reportMessage = 'Make a report for $description at $location and population is $population.';

  if (_uploadedImageUrl == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please upload an image first')),
    );
    return;
  }

  setState(() {
    _isAnalyzing = true;
  });

  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    },
  );

  try {
    final uri = Uri.parse('http://40.127.8.37:9000/analyze-image-with-query');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'image_url': _uploadedImageUrl,
        'query': reportMessage, 
      }),
    );

    if (response.statusCode == 200) {
      var jsonResponse = jsonDecode(response.body);
      String analysis = jsonResponse['analysis'].toString();

      setState(() {
        _analysisResult = analysis;
      });
    } else {
      throw Exception('Failed to analyze image: ${response.statusCode}');
    }
  } catch (e) {
    setState(() {
      _analysisResult = 'Error: $e';
    });
  } finally {
    // Dismiss the loading dialog
    Navigator.of(context).pop();
    setState(() {
      _isAnalyzing = false;
    });
  }
}


Future<void> submitReport() async {
  String description = _descriptionController.text;
  String location = _locationController.text;
  String population = _populationController.text;

  String reportMessage = 'Make a report for $description at $location and population is $population.';

  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    },
  );

  // Send report to API
  final uri = Uri.parse('http://40.127.8.37:9000/generate');

  try {
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'message': reportMessage}),
    );

    if (response.statusCode == 200) {
      // Handle successful response
      var jsonResponse = jsonDecode(response.body);
      print('Response body $jsonResponse');
      var responseList = jsonResponse['response'];
      print('Response: $responseList');
      String reportContent = responseList[2]['content'].toString();

      // Update the state to show the report content
      setState(() {
        _reportContent = reportContent;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report submitted: $reportContent')),
      );
    } else {
      throw Exception('Failed to submit report');
    }
  } catch (e) {
    print('Error submitting report: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to submit report: $e')),
    );
  } finally {
    // Dismiss the loading dialog
    Navigator.of(context).pop();
  }
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _image == null
                  ? const Text('No image selected.')
                  : Image.file(_image!, height: 200),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: getImageFromGallery,
                child: const Text('Pick Image from Gallery'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: getImageFromCamera,
                child: const Text('Take Picture with Camera'),
              ),
              const SizedBox(height: 20),

              // Population input field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: TextField(
                  controller: _populationController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Population',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),

              // Location input field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Location',
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),

              // Description input field with multiple lines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Description',
                  ),
                  keyboardType: TextInputType.multiline,
                  maxLines: 5,
                  minLines: 5,
                ),
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isUploading ? null : uploadImage,
                child: _isUploading
                    ? const CircularProgressIndicator()
                    : const Text('Upload Image'),
              ),
              if (_uploadedImageUrl != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Uploaded URL: $_uploadedImageUrl'),
                ),
              const SizedBox(height: 20),
              
              // Submit report button
              ElevatedButton(
                onPressed: submitReport,
                child: const Text('Submit Report'),
              ),

                                          const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isAnalyzing ? null : analyzeImage,
                child: _isAnalyzing
                    ? const CircularProgressIndicator()
                    : const Text('Analyze Image'),
              ),


              const SizedBox(height: 20),
              if (_analysisResult.isNotEmpty)
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Analysis Result: $_analysisResult',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),

              const SizedBox(height: 20),


              // Card displaying network information
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Network Information',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text('Connection Status: $_connectionStatus'),
                      const SizedBox(height: 10),
                      Text('Network Details:\n$_networkDetails'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),



              // New Card to display the report content
              if (_reportContent.isNotEmpty)
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generated Report',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(_reportContent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
