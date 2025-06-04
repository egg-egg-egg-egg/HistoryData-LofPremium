import os
import time
from lof import lof_premium
import datetime
import chinese_calendar

def is_a_share_trading_day(date=None):
    """判断是否为A股交易日"""
    if date is None:
        date = time.localtime()
    y, m, d = date.tm_year, date.tm_mon, date.tm_mday
    return chinese_calendar.is_workday(datetime.date(y, m, d))

def save_lof_data():
    if not is_a_share_trading_day():
        print("今日非交易日，跳过数据保存")
        return

    lof_premium().to_csv(f"./data/{datetime.datetime.now().strftime('%Y%m%d')}.csv", encoding='utf-8-sig')

if __name__ == "__main__":
    save_lof_data()
