import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../trading/investment_style.dart';
import '../data/app_data_manager.dart';

// Events
abstract class AutoTradingEvent {}

class StartAutoTrading extends AutoTradingEvent {
  final InvestmentStyle style;
  final List<String> indicators;
  
  StartAutoTrading({
    required this.style,
    required this.indicators,
  });
}

class StopAutoTrading extends AutoTradingEvent {}

class UpdateAutoTradingStatus extends AutoTradingEvent {
  final bool isRunning;
  
  UpdateAutoTradingStatus(this.isRunning);
}

// States
abstract class AutoTradingState {
  bool get isRunning;
}

class AutoTradingInitial extends AutoTradingState {
  final bool isRunning;
  final InvestmentStyle? currentStyle;
  final List<String> currentIndicators;
  final String? lastSignal;
  final DateTime? lastSignalTime;
  
  AutoTradingInitial({
    this.isRunning = false,
    this.currentStyle,
    this.currentIndicators = const [],
    this.lastSignal,
    this.lastSignalTime,
  });
}

class AutoTradingLoading extends AutoTradingState {
  final bool isRunning;
  final InvestmentStyle? currentStyle;
  final List<String> currentIndicators;
  
  AutoTradingLoading({
    this.isRunning = false,
    this.currentStyle,
    this.currentIndicators = const [],
  });
}

class AutoTradingRunning extends AutoTradingState {
  final bool isRunning;
  final InvestmentStyle currentStyle;
  final List<String> currentIndicators;
  final String? lastSignal;
  final DateTime? lastSignalTime;
  final Map<String, dynamic> positions;
  final double capital;
  final double dailyLoss;
  
  AutoTradingRunning({
    required this.isRunning,
    required this.currentStyle,
    required this.currentIndicators,
    this.lastSignal,
    this.lastSignalTime,
    required this.positions,
    required this.capital,
    required this.dailyLoss,
  });
}

class AutoTradingStopped extends AutoTradingState {
  final bool isRunning;
  final InvestmentStyle? lastStyle;
  final List<String> lastIndicators;
  final String? lastSignal;
  final DateTime? lastSignalTime;
  
  AutoTradingStopped({
    this.isRunning = false,
    this.lastStyle,
    this.lastIndicators = const [],
    this.lastSignal,
    this.lastSignalTime,
  });
}

class AutoTradingError extends AutoTradingState {
  final String message;
  final bool isRunning;
  final InvestmentStyle? currentStyle;
  final List<String> currentIndicators;
  
  AutoTradingError({
    required this.message,
    this.isRunning = false,
    this.currentStyle,
    this.currentIndicators = const [],
  });
}

// Bloc
class AutoTradingBloc extends Bloc<AutoTradingEvent, AutoTradingState> {
  AutoTradingBloc() : super(AutoTradingInitial()) {
    on<StartAutoTrading>(_onStartAutoTrading);
    on<StopAutoTrading>(_onStopAutoTrading);
    on<UpdateAutoTradingStatus>(_onUpdateAutoTradingStatus);
  }

  Future<void> _onStartAutoTrading(StartAutoTrading event, Emitter<AutoTradingState> emit) async {
    try {
      emit(AutoTradingLoading(
        isRunning: true,
        currentStyle: event.style,
        currentIndicators: event.indicators,
      ));

      // 상태 저장 (전역)
      await AppDataManager.instance.setAutoTradingStatus(true);
      print('🤖 자동매매 BLoC: UI 상태 업데이트 (Cycle 사용)');

      emit(AutoTradingRunning(
        isRunning: true,
        currentStyle: event.style,
        currentIndicators: event.indicators,
        positions: const {},
        capital: 0.0,
        dailyLoss: 0.0,
      ));

    } catch (e) {
      emit(AutoTradingError(
        message: 'AI 자동매매 시작 실패: $e',
        isRunning: false,
        currentStyle: event.style,
        currentIndicators: event.indicators,
      ));
    }
  }

  Future<void> _onStopAutoTrading(StopAutoTrading event, Emitter<AutoTradingState> emit) async {
    try {
      final currentState = state;
      final lastStyle = currentState is AutoTradingRunning ? currentState.currentStyle : null;
      final lastIndicators = currentState is AutoTradingRunning ? currentState.currentIndicators : <String>[];
      final lastSignal = currentState is AutoTradingRunning ? currentState.lastSignal : null;
      final lastSignalTime = currentState is AutoTradingRunning ? currentState.lastSignalTime : null;

      await AppDataManager.instance.setAutoTradingStatus(false);

      emit(AutoTradingStopped(
        isRunning: false,
        lastStyle: lastStyle,
        lastIndicators: lastIndicators,
        lastSignal: lastSignal,
        lastSignalTime: lastSignalTime,
      ));

    } catch (e) {
      emit(AutoTradingError(
        message: 'AI 자동매매 중지 실패: $e',
        isRunning: false,
      ));
    }
  }

  void _onUpdateAutoTradingStatus(UpdateAutoTradingStatus event, Emitter<AutoTradingState> emit) {
    final currentState = state;
    
    if (event.isRunning) {
      // 이미 실행 중이면 상태만 업데이트
      if (currentState is AutoTradingRunning) {
        emit(AutoTradingRunning(
          isRunning: true,
          currentStyle: currentState.currentStyle,
          currentIndicators: currentState.currentIndicators,
          lastSignal: currentState.lastSignal,
          lastSignalTime: currentState.lastSignalTime,
          positions: currentState.positions,
          capital: currentState.capital,
          dailyLoss: currentState.dailyLoss,
        ));
      }
    } else {
      // 중지 상태로 업데이트
      if (currentState is AutoTradingRunning) {
        emit(AutoTradingStopped(
          isRunning: false,
          lastStyle: currentState.currentStyle,
          lastIndicators: currentState.currentIndicators,
          lastSignal: currentState.lastSignal,
          lastSignalTime: currentState.lastSignalTime,
        ));
      }
    }
  }

  @override
  Future<void> close() {
    return super.close();
  }
}
