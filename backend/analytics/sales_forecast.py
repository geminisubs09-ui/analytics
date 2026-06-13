import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, apply_analytics_filters
from datetime import datetime, timedelta

router = APIRouter()

@router.get("/analytics/sales-forecast")
def get_sales_forecast(start_date: str = None, end_date: str = None, party: str = None, forecast_days: int = 30):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    
    if vouchers_df.empty:
        return []
        
    vouchers_df, _ = apply_analytics_filters(
        vouchers_df=vouchers_df,
        start_date=start_date,
        end_date=end_date,
        party=party
    )
    
    if vouchers_df.empty:
        return []
        
    # Group by date to get daily revenue
    daily_sales = vouchers_df.groupby('date')['revenue'].sum().reset_index()
    daily_sales['date'] = pd.to_datetime(daily_sales['date'])
    daily_sales = daily_sales.sort_values(by='date')
    
    # We need a continuous date range to properly calculate moving averages
    min_date = daily_sales['date'].min()
    max_date = daily_sales['date'].max()
    
    if pd.isna(min_date) or pd.isna(max_date):
        return []
        
    date_range = pd.date_range(start=min_date, end=max_date)
    daily_sales = daily_sales.set_index('date').reindex(date_range).fillna(0.0).reset_index()
    daily_sales.rename(columns={'index': 'date'}, inplace=True)
    
    # Calculate 7-day moving average
    daily_sales['ma_7'] = daily_sales['revenue'].rolling(window=7, min_periods=1).mean()
    
    # Get the last moving average to use as base for forecast
    last_ma = daily_sales.iloc[-1]['ma_7']
    
    results = []
    
    # Return last 30 days of historical data for context
    historical = daily_sales.tail(30)
    for _, row in historical.iterrows():
        results.append({
            "date": row['date'].strftime('%Y-%m-%d'),
            "actual_revenue": round(row['revenue'], 2),
            "forecast_revenue": None,
            "is_forecast": False
        })
        
    # Generate forecast
    for i in range(1, forecast_days + 1):
        forecast_date = max_date + timedelta(days=i)
        results.append({
            "date": forecast_date.strftime('%Y-%m-%d'),
            "actual_revenue": None,
            "forecast_revenue": round(last_ma, 2),
            "is_forecast": True
        })
        
    return results
