import 'package:flutter/material.dart';

typedef RefreshableWidgetBuilder = Widget Function(BuildContext context);

class RefreshableTab extends StatefulWidget {
  final RefreshableWidgetBuilder builder;
  const RefreshableTab({Key? key, required this.builder}) : super(key: key);

  @override
  RefreshableTabState createState() => RefreshableTabState();
}

class RefreshableTabState extends State<RefreshableTab> {
  late Future<void> _refreshFuture;

  @override
  void initState() {
    super.initState();
    _refreshFuture = Future.value();
  }

  Future<void> refresh() async {
    // Try to call reloadData on the child widget's state
    // Directly call reloadData on our child if possible
    final state = (widget.key is GlobalKey)
        ? (widget.key as GlobalKey).currentState
        : null;
    if (state != null) {
      try {
        // Use dynamic invocation to call reloadData if it exists
        final dynamic dynState = state;
        final result = dynState.reloadData();
        _refreshFuture = result is Future ? result : Future.value();
        setState(() {});
        return;
      } catch (e) {
        // reloadData not found, fallback
      }
    }
    setState(() {
      _refreshFuture = Future.value();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: FutureBuilder<void>(
        future: _refreshFuture,
        builder: (context, snapshot) {
          return widget.builder(context);
        },
      ),
    );
  }
}