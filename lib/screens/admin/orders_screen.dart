import 'package:flutter/material.dart';

class OrdersScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Order Pipeline"),
          bottom: TabBar(tabs: [
            Tab(text: "New"),
            Tab(text: "Active"),
            Tab(text: "Done"),
          ]),
        ),
        body: TabBarView(
          children: [
            _buildOrderList("New"),
            _buildOrderList("Active"),
            _buildOrderList("Done"),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(String status) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => ListTile(
        title: Text("Order #00${index + 10}"),
        subtitle: Text("Status: $status"),
        trailing: Icon(Icons.info_outline),
      ),
    );
  }
}