import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/finance/widgets/category_bar_chart.dart';
import 'package:frontend/features/finance/widgets/category_pie_chart.dart';
import 'package:frontend/features/auth/models/user.dart';

void main() {
  group('Chart Widget Tests', () {
    testWidgets('CategoryPieChart renders with empty data', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CategoryPieChart(categoryExpenses: {}),
        ),
      ));

      expect(find.text('Keine Ausgaben vorhanden'), findsOneWidget);
    });

    testWidgets('CategoryPieChart renders with mock expenses', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CategoryPieChart(categoryExpenses: {
            'Lebensmittel': 150.0,
            'Miete': 800.0,
          }),
        ),
      ));

      // It should display the legend items
      expect(find.textContaining('Lebensmittel'), findsWidgets);
      expect(find.textContaining('Miete'), findsWidgets);
      
      // Render components successfully
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('CategoryBarChart renders properly', (WidgetTester tester) async {
      final mockData = [
        const FlSpot(0, 100),
        const FlSpot(1, 150),
        const FlSpot(2, 50),
      ];

      // Create a mock user if necessary, or pass null if dynamic is allowed
      final mockUser = UserModel(
        uid: 1, 
        email: 'test@test.com', 
        password: 'hash', 
        displayName: 'test', 
        age: 25, 
        phonenumber: '123'
      );

      await tester.pumpWidget(MaterialApp(
        home: CategoryBarChart(
          data: mockData,
          selectedCategory: 'Lebensmittel',
          user: mockUser,
        ),
      ));

      // Checks if title is presented
      expect(find.text('Lebensmittel'), findsWidgets);
      
      // Checks if BarChart renders
      expect(find.byType(BarChart), findsOneWidget);
    });
  });
}
