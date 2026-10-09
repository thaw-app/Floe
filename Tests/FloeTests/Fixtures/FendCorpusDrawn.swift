//
//  FendCorpusDrawn.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3
//
//  Written by the replay suite when FLOE_WRITE_FEND_LEDGER=1. Do not add a line by hand.

/// What the calculator draws for each input of fend's tests it answers, one to a line: the input, a tab, the text.
/// A change of colour is marked after the text it applies to. A change to a line is a change to what people see.
enum FendCorpusDrawn {
    static let text = ##"""
    pi	≈ ⟨secondary⟩3.1415926536⟨primary⟩
    pi * 2	≈ ⟨secondary⟩6.2831853072⟨primary⟩
    2 pi	≈ ⟨secondary⟩6.2831853072⟨primary⟩
    00	0⟨primary⟩
    000000	0⟨primary⟩
    000000.01	0.01⟨primary⟩
    0000001.01	1.01⟨primary⟩
    0b01	1⟨primary⟩
    0x0000_00ff	255⟨primary⟩
    10#04	1,0#4⟨primary⟩
    1e01	10⟨primary⟩
    1e-01	0.1⟨primary⟩
    1E3	1,000⟨primary⟩
    1E10	10,000,000,000⟨primary⟩
    1E-3	0.001⟨primary⟩
    0b10E100 to decimal	32⟨primary⟩
    0.(3) to float	0.(3)⟨primary⟩
    0.(33) to float	0.(3)⟨primary⟩
    0.(34) to float	0.(34)⟨primary⟩
    0.(12345) to float	0.(12345)⟨primary⟩
    0.(0) to float	0⟨primary⟩
    0.123(00) to float	0.123⟨primary⟩
    0.0(34) to float	0.0(34)⟨primary⟩
    0.00(34) to float	0.00(34)⟨primary⟩
    0.0000(34) to float	0.0000(34)⟨primary⟩
    0.123434(34) to float	0.12(34)⟨primary⟩
    0.123434(34)i to float	0.12(34)i⟨primary⟩
    0.(3) + 0.123434(34)i to float	0.(3) + 0.12(34)i⟨primary⟩
    6#0.(1) to float	6#0.(1)⟨primary⟩
    6#0.(1) to float in base 10	0.2⟨primary⟩
    2*2	4⟨primary⟩
    \n2\n*\n2\n	4⟨primary⟩
    315427679023453451289740 * 927346502937456234523452	≈ ⟨secondary⟩2.925107551⟨primary⟩ × ⟨secondary⟩10⁴⁷⟨primary⟩
    pi * pi	≈ ⟨secondary⟩9.869604402⟨primary⟩
    4pi + 1	≈ ⟨secondary⟩13.5663706144⟨primary⟩
    -sin (-pi/2)	1⟨primary⟩
    +sin (-pi/2)	-1⟨primary⟩
    cos! 0	1⟨primary⟩
    sqrt! 16	24⟨primary⟩
    cos^2 pi	1⟨primary⟩
    sin pi/cos pi	0⟨primary⟩
    sin + 1) pi	1⟨primary⟩
    3sin pi	0⟨primary⟩
    (-sqrt) 4	-2⟨primary⟩
    -sqrt 4	-2⟨primary⟩
    sin^-1	asin⟨primary⟩
    sin^-1 0.5	≈ ⟨secondary⟩0.5235987756⟨primary⟩
    sin^-1 (sin 0.5	≈ ⟨secondary⟩0.5⟨primary⟩
    (sin^-1)^-1	sin⟨primary⟩
    cos^-1	acos⟨primary⟩
    tan^-1	atan⟨primary⟩
    asin^-1	sin⟨primary⟩
    acos^-1	cos⟨primary⟩
    atan^-1	tan⟨primary⟩
    sinh^-1	asinh⟨primary⟩
    cosh^-1	acosh⟨primary⟩
    tanh^-1	atanh⟨primary⟩
    asinh^-1	sinh⟨primary⟩
    acosh^-1	cosh⟨primary⟩
    atanh^-1	tanh⟨primary⟩
    2+2	4⟨primary⟩
    \n2\n+\n2\n	4⟨primary⟩
    +2	2⟨primary⟩
    ++++2	2⟨primary⟩
    315427679023453451289740 + 927346502937456234523452	≈ ⟨secondary⟩1.242774182⟨primary⟩ × ⟨secondary⟩10²⁴⟨primary⟩
    -0	0⟨primary⟩
    2-2	0⟨primary⟩
    3-2	1⟨primary⟩
    2-3	-1⟨primary⟩
    -2	-2⟨primary⟩
    --2	2⟨primary⟩
    ---2	-2⟨primary⟩
    -(--2)	-2⟨primary⟩
    \n2\n-\n64\n	-62⟨primary⟩
    315427679023453451289740 - 927346502937456234523452	≈ ⟨secondary⟩-6.119188239⟨primary⟩ × ⟨secondary⟩10²³⟨primary⟩
    3pi - 2pi	≈ ⟨secondary⟩3.1415926536⟨primary⟩
    4pi-1)/pi	≈ ⟨secondary⟩3.6816901138⟨primary⟩
    36893488123704996004 - 18446744065119617025	≈ ⟨secondary⟩1.844674406⟨primary⟩ × ⟨secondary⟩10¹⁹⟨primary⟩
    sqrt (1/2)	≈ ⟨secondary⟩0.7071067812⟨primary⟩
    sqrt 0	0⟨primary⟩
    sqrt 1	1⟨primary⟩
    sqrt 2	≈ ⟨secondary⟩1.4142135624⟨primary⟩
    sqrt pi	≈ ⟨secondary⟩1.7724538509⟨primary⟩
    sqrt 4	2⟨primary⟩
    sqrt 9	3⟨primary⟩
    sqrt 16	4⟨primary⟩
    sqrt 25	5⟨primary⟩
    sqrt 36	6⟨primary⟩
    sqrt 49	7⟨primary⟩
    sqrt 64	8⟨primary⟩
    sqrt 81	9⟨primary⟩
    sqrt 100	10⟨primary⟩
    sqrt 10000	100⟨primary⟩
    sqrt 1000000	1,000⟨primary⟩
    sqrt 0.25	0.5⟨primary⟩
    sqrt 0.0625	0.25⟨primary⟩
    cbrt 0	0⟨primary⟩
    cbrt 1	1⟨primary⟩
    cbrt 8	2⟨primary⟩
    cbrt 27	3⟨primary⟩
    cbrt 64	4⟨primary⟩
    cbrt (1/8)	0.5⟨primary⟩
    cbrt (125/8)	2.5⟨primary⟩
    sqrt(kg^2)	1 kg⟨primary⟩
    (sqrt kg)^2	1 kg⟨primary⟩
    1 lightyear to parsecs	≈ ⟨secondary⟩0.3066013938 parsecs⟨primary⟩
    2+2*3	8⟨primary⟩
    2*2+3	7⟨primary⟩
    2+2+3	7⟨primary⟩
    2+2-3	1⟨primary⟩
    2-2+3	3⟨primary⟩
    2-2-3	-3⟨primary⟩
    2*2*3	12⟨primary⟩
    2*2*-3	-12⟨primary⟩
    2*-2*3	-12⟨primary⟩
    -2*2*3	-12⟨primary⟩
    -2*-2*3	12⟨primary⟩
    -2*2*-3	12⟨primary⟩
    2*-2*-3	12⟨primary⟩
    -2*-2*-3	-12⟨primary⟩
    -2*-2*-3/2	-6⟨primary⟩
    -2*-2*-3/-2	6⟨primary⟩
    -3 -1/2	-3.5⟨primary⟩
    1 YiB to bytes	≈ ⟨secondary⟩1.20892582⟨primary⟩ × ⟨secondary⟩10²⁴ bytes⟨primary⟩
    1/1	1⟨primary⟩
    1/2	0.5⟨primary⟩
    1/4	0.25⟨primary⟩
    1/8	0.125⟨primary⟩
    1/16	0.0625⟨primary⟩
    1/32	0.03125⟨primary⟩
    1/64	0.015625⟨primary⟩
    2/64	0.03125⟨primary⟩
    4/64	0.0625⟨primary⟩
    8/64	0.125⟨primary⟩
    16/64	0.25⟨primary⟩
    32/64	0.5⟨primary⟩
    64/64	1⟨primary⟩
    2/1	2⟨primary⟩
    27/3	9⟨primary⟩
    100/4	25⟨primary⟩
    100/5	20⟨primary⟩
    18446744073709551616/2	≈ ⟨secondary⟩9.223372037⟨primary⟩ × ⟨secondary⟩10¹⁸⟨primary⟩
    184467440737095516160000000000000/2	≈ ⟨secondary⟩9.223372037⟨primary⟩ × ⟨secondary⟩10³¹⟨primary⟩
    (3pi) / (2pi)	1.5⟨primary⟩
    0.0	0⟨primary⟩
    0.000000	0⟨primary⟩
    0.01000	0.01⟨primary⟩
    .1	0.1⟨primary⟩
    .1e-1	0.01⟨primary⟩
    001.01000	1.01⟨primary⟩
    1.00000001 as 1 dp	≈ ⟨secondary⟩1⟨primary⟩
    1.00000001 as 2 dp	≈ ⟨secondary⟩1⟨primary⟩
    1.00000001 as 3 dp	≈ ⟨secondary⟩1⟨primary⟩
    1.00000001 as 4 dp	≈ ⟨secondary⟩1⟨primary⟩
    1.00000001 as 10 dp	1.00000001⟨primary⟩
    1.00000001 as 30 dp	1.00000001⟨primary⟩
    1.00000001 as 1000 dp	1.00000001⟨primary⟩
    1.00000001 as 0 dp	≈ ⟨secondary⟩1⟨primary⟩
    .1(0)	0.1⟨primary⟩
    .1( 0)	0⟨primary⟩
    .1 ( 0)	0⟨primary⟩
    2.0(e)	≈ ⟨secondary⟩5.4365636569⟨primary⟩
    2.0(ln 5)	≈ ⟨secondary⟩3.2188758249⟨primary⟩
    2 (5)	10⟨primary⟩
    2( 5)	10⟨primary⟩
    60153992292001127921539815855494266880 / 9223372036854775808	≈ ⟨secondary⟩6.521908913⟨primary⟩ × ⟨secondary⟩10¹⁸⟨primary⟩
    (1)	1⟨primary⟩
    (0.0)	0⟨primary⟩
    (1+-2)	-1⟨primary⟩
    1+2*3	7⟨primary⟩
    (1+2)*3	9⟨primary⟩
    ((1+2))*3	9⟨primary⟩
    ((1)+2)*3	9⟨primary⟩
    (1+(2))*3	9⟨primary⟩
    (1+(2)*3)	7⟨primary⟩
    1+(2*3)	7⟨primary⟩
    1+((2 )*3)	7⟨primary⟩
     1 + ( (\r\n2 ) * 3 ) 	7⟨primary⟩
    2*(1+3	8⟨primary⟩
    4+5+6)*(1+2	45⟨primary⟩
    4+5+6))*(1+2	45⟨primary⟩
    1^1	1⟨primary⟩
    1**1	1⟨primary⟩
    1**1.0	1⟨primary⟩
    1.0**1	1⟨primary⟩
    2^4	16⟨primary⟩
    4^2	16⟨primary⟩
    4^3	64⟨primary⟩
    4^(3^1)	64⟨primary⟩
    4^3^1	64⟨primary⟩
    (4^3)^1	64⟨primary⟩
    (2^3)^4	4,096⟨primary⟩
    2^3^2	512⟨primary⟩
    (2^3)^2	64⟨primary⟩
    4^0.5	2⟨primary⟩
    4^(1/2)	2⟨primary⟩
    4^(1/4)	≈ ⟨secondary⟩1.4142135624⟨primary⟩
    (2/3)^(4/5)	≈ ⟨secondary⟩0.7229811808⟨primary⟩
    5.2*10^15*300^(3/2)	≈ ⟨secondary⟩2.70199926⟨primary⟩ × ⟨secondary⟩10¹⁹⟨primary⟩
    pi^10	≈ ⟨secondary⟩93,648.047476083⟨primary⟩
    0^1	0⟨primary⟩
    1^0	1⟨primary⟩
    1^1e1000	1⟨primary⟩
    4^i	≈ ⟨secondary⟩0.1834569747 + 0.9830277404i⟨primary⟩
    i^i	≈ ⟨secondary⟩0.2078795764⟨primary⟩
    kg^(approx. 1)	≈ ⟨secondary⟩1 kg⟨primary⟩
    -0.125	-0.125⟨primary⟩
    2^1^2	2⟨primary⟩
    2^(1^2)	2⟨primary⟩
    2^(1)	2⟨primary⟩
    2 * (-2^3)	-16⟨primary⟩
    2 * -2^3	-16⟨primary⟩
    2^-3 * 4	0.5⟨primary⟩
    2^3 * 4	32⟨primary⟩
    -2^-3	-0.125⟨primary⟩
    2 * -3 * 4	-24⟨primary⟩
    4^-1^2	0.25⟨primary⟩
    2^-3^4	≈ ⟨secondary⟩4.135903063⟨primary⟩ × ⟨secondary⟩10⁻²⁵⟨primary⟩
    3i+4	4 +, 3i⟨primary⟩
    (3i+4) + i	4 +, 4i⟨primary⟩
    3i+(4 + i)	4 +, 4i⟨primary⟩
    -3i	-3i⟨primary⟩
    i/i	1⟨primary⟩
    i*i	-1⟨primary⟩
    i*i*i	-i⟨primary⟩
    i*i*i*i	1⟨primary⟩
    -3+i	-3 ,+ i⟨primary⟩
    1+i	1 ,+ i⟨primary⟩
    1-i	1 ,- i⟨primary⟩
    -1 + i	-1 ,+ i⟨primary⟩
    -1 - i	-1 ,- i⟨primary⟩
    -1 - 2i	-,1 -, 2i⟨primary⟩
    -1 - 0.5i	-1 ,- 0.5i⟨primary⟩
    -1 - 0.5i + 1.5i	-1 ,+ i⟨primary⟩
    -i	-i⟨primary⟩
    +i	i⟨primary⟩
    i/3	i/3⟨primary⟩
    2i/3	2,i/3⟨primary⟩
    2i/-3-1	-1 ,- 2,i/3⟨primary⟩
    1_1	11⟨primary⟩
    11_1	111⟨primary⟩
    1_1_1	111⟨primary⟩
    123_456_789_123	123,456,789,123⟨primary⟩
    1_2_3_4_5_6	123,456⟨primary⟩
    1.1_1	1.11⟨primary⟩
    1_1.1_1	11.11⟨primary⟩
    1,1	11⟨primary⟩
    11,1	111⟨primary⟩
    1,1,1	111⟨primary⟩
    123,456,789,123	123,456,789,123⟨primary⟩
    1,2,3,4,5,6	123,456⟨primary⟩
    1.1,1	1.11⟨primary⟩
    1,1.1,1	11.11⟨primary⟩
    0x10	16⟨primary⟩
    0o10	8⟨primary⟩
    0b10	2⟨primary⟩
    0x10 - 1	F₁₆⟨primary⟩
    0x0 + sqrt 16	4₁₆⟨primary⟩
    16#0 + sqrt 16	1,6#4⟨primary⟩
    0 + 6#100	36⟨primary⟩
    0 + 36#z	35⟨primary⟩
    16#dead_beef	16,#de,adb,eef⟨primary⟩
    16#DEAD_BEEF	16,#de,adb,eef⟨primary⟩
    16#D3AD_BEEF	16,#d3,adb,eef⟨primary⟩
    0 + 36#ii	666⟨primary⟩
    19#i/i	-,19#,i i⟨primary⟩
    0+36#0123456789abcdefghijklmnopqrstuvwxyz	≈ ⟨secondary⟩8.684682361⟨primary⟩ × ⟨secondary⟩10⁵²⟨primary⟩
    36#0 + 86846823611197163108337531226495015298096208677436155	36,#12,345,678,9ab,cde,fgh,ijk,lmn,opq,rst,uvw,xyz⟨primary⟩
    18#100/65537 i	18#,100,i/1,8#b,44h⟨primary⟩
    19#100/65537 i	1,9#1,00 ,i/1,9#9,aa6⟨primary⟩
    3 electron_charge	4.806529902⟨primary⟩ × ⟨secondary⟩10⁻¹⁹ coulomb⟨primary⟩
    e to 1	≈ ⟨secondary⟩2.7182818285⟨primary⟩
    e in binary	≈ ⟨secondary⟩1,0.10,1110,0000₂⟨primary⟩
    16 to base 2	1,0000₂⟨primary⟩
    0x10ffff to decimal	1,114,111⟨primary⟩
    0o400 to decimal	256⟨primary⟩
    100 to base 6	244₆⟨primary⟩
    65536 to hex	1,0000₁₆⟨primary⟩
    65536 to octal	200,000₈⟨primary⟩
    1e10	10,000,000,000⟨primary⟩
    1.5e10	15,000,000,000⟨primary⟩
    0b1e10	100₂⟨primary⟩
    0b1e+10	100₂⟨primary⟩
    0 + 0b1e100	16⟨primary⟩
    0 + 0b1e1000	256⟨primary⟩
    0 + 0b1e10000	65,536⟨primary⟩
    0 + 0b1e100000	4,294,967,296⟨primary⟩
    10#1e10	10,#10,000,000,000⟨primary⟩
    0 + 0b1e10000000	≈ ⟨secondary⟩3.402823669⟨primary⟩ × ⟨secondary⟩10³⁸⟨primary⟩
    1.5e-1	0.15⟨primary⟩
    1.5e0	1.5⟨primary⟩
    1.5e-0	1.5⟨primary⟩
    1.5e+0	1.5⟨primary⟩
    1.5e1	15⟨primary⟩
    1.5e+1	15⟨primary⟩
    0 + 0b1e-110	0.015625⟨primary⟩
    e	≈ ⟨secondary⟩2.7182818285⟨primary⟩
    2 e	≈ ⟨secondary⟩5.4365636569⟨primary⟩
    2e	≈ ⟨secondary⟩5.4365636569⟨primary⟩
    2e/2	≈ ⟨secondary⟩2.7182818285⟨primary⟩
    2e / 2	≈ ⟨secondary⟩2.7182818285⟨primary⟩
    e^10	≈ ⟨secondary⟩22,026.4657948067⟨primary⟩
    e^2.72	≈ ⟨secondary⟩15.1803222450⟨primary⟩
    1kg + 1g	1.001 kg⟨primary⟩
    1kg + 100g	1.1 kg⟨primary⟩
    0g + 1kg + 100g	1,100 g⟨primary⟩
    0g + 1kg	1,000 g⟨primary⟩
    1/0.5 kg	2 kg⟨primary⟩
    1/(1/0.5 kg)	0.5 kg^-1⟨primary⟩
    cbrt (1kg)	1 kg^(1/3)⟨primary⟩
    1 kg + i g	(1 ,+ 0.001i) kg⟨primary⟩
    abs 2	2⟨primary⟩
    (4)(6)	24⟨primary⟩
    5(6)	30⟨primary⟩
    3’6”	3.5’⟨primary⟩
    5 feet 12 inch	6 feet⟨primary⟩
    3'6"	3.5'⟨primary⟩
    3 m 15 cm	3.15 m⟨primary⟩
    5%	5%⟨primary⟩
    5% to %	5%⟨primary⟩
    5% + 0.1	15%⟨primary⟩
    5% + 1	105%⟨primary⟩
    0.1 + 5%	0.105⟨primary⟩
    1 + 5%	1.05⟨primary⟩
    5% * 5%	0.25%⟨primary⟩
    5% * 8 kg	0.4 kg⟨primary⟩
    5% * 100	5⟨primary⟩
    5% of 100	5⟨primary⟩
    2 + 5% of 200	12⟨primary⟩
    (2 + 5)% of 200	14⟨primary⟩
    0m + 1kph * 1 hr	1,000 m⟨primary⟩
    0GiB + 1GB	≈ ⟨secondary⟩0.9313225746 GiB⟨primary⟩
    0m/s + 1 km/hr	≈ ⟨secondary⟩0.2777777778 m/s⟨primary⟩
    0m/s + i km/hr	5i,/18 m/s⟨primary⟩
    0m/s + i kilometers per hour	5i,/18 m/s⟨primary⟩
    0m/s + (1 + i) km/hr	(5,/18, + ,5i/,18) m/s⟨primary⟩
    365.25 light days to ly	1 ly⟨primary⟩
    365.25 light days as ly	1 ly⟨primary⟩
    1 light year	1 light_year⟨primary⟩
    5pi	≈ ⟨secondary⟩15.7079632679⟨primary⟩
    5 pi/2	≈ ⟨secondary⟩7.8539816340⟨primary⟩
    5 i/2	2.5i⟨primary⟩
    1psi as kPa as 5dp	≈ ⟨secondary⟩6.89476 kPa⟨primary⟩
    1NM to m	1,852 m⟨primary⟩
    1NM + 1cm as m	1,852.01 m⟨primary⟩
    1 m / (s kg cd)	1 m s^-1 kg^-1 cd^-1⟨primary⟩
    1 watt hour / lb	1 watt hour/lb⟨primary⟩
    4 watt hours / lb	4 watt hours/lb⟨primary⟩
    1 second second	1 second^2⟨primary⟩
    2 second seconds	2 seconds^2⟨primary⟩
    1 lb^-1	1 lb^-1⟨primary⟩
    2 lb^-1	2 lb^-1⟨primary⟩
    2 lb^-1 kg^-1	0.90718474 lb^-2⟨primary⟩
    1 lb^-1 kg^-1	0.45359237 lb^-2⟨primary⟩
    0.5 light year	0.5 light_years⟨primary⟩
    1 lightyear / second	1 lightyear/second⟨primary⟩
    2 lightyears / second	2 lightyears/second⟨primary⟩
    2 lightyears second^-1 lb^-1	2 lightyears second^-1 lb^-1⟨primary⟩
    1 feet	1 foot⟨primary⟩
    5 foot	5 feet⟨primary⟩
    5 foot 2 inches	≈ ⟨secondary⟩5.1666666667 feet⟨primary⟩
    5 foot 1 inch 1 inch	≈ ⟨secondary⟩5.1666666667 feet⟨primary⟩
    5 (abs 4)	20⟨primary⟩
    1 2/3 to fraction	5/3⟨primary⟩
    5/3	≈ ⟨secondary⟩1.6666666667⟨primary⟩
    4 + 1 2/3	≈ ⟨secondary⟩5.6666666667⟨primary⟩
    -8 1/2	-8.5⟨primary⟩
    -8 1/2'	-8.5'⟨primary⟩
    1.(3)i	1, 1/,3 i⟨primary⟩
    1*1 1/2	1.5⟨primary⟩
    2*1 1/2	3⟨primary⟩
    3*2*1 1/2	9⟨primary⟩
    3 + 2*1 1/2	6⟨primary⟩
    abs 2*1 1/2	3⟨primary⟩
    1 1/2 m/s^2	1.5 m/s^2⟨primary⟩
    1' to inches	12 inches⟨primary⟩
    abs 1	1⟨primary⟩
    abs i	1⟨primary⟩
    abs (-1)	1⟨primary⟩
    abs (-i)	1⟨primary⟩
    abs (2i)	2⟨primary⟩
    abs (1 + i)	≈ ⟨secondary⟩1.4142135624⟨primary⟩
    2 kg^2	2 kg^2⟨primary⟩
    ((1/4) kg)^-2	16 kg^-2⟨primary⟩
    1 N - 1 kg m s^-2	0 N⟨primary⟩
    1 J - 1 kg m^2 s^-2 + 1 kg / (m^-2 s^2)	1 J⟨primary⟩
    2^abs 1	2⟨primary⟩
    3*-2	-6⟨primary⟩
    -3*-2	6⟨primary⟩
    -3*2	-6⟨primary⟩
    1 2/3 + 4 5/6	6.5⟨primary⟩
    1 2/3 + -4 5/6	≈ ⟨secondary⟩-3.1666666667⟨primary⟩
    1 2/3 - 4 5/6	≈ ⟨secondary⟩-3.1666666667⟨primary⟩
    1 2/3 - 4 + 5/6	-1.5⟨primary⟩
    1 barn to m^2	10⁻²⁸ m^2⟨primary⟩
    1L to m^3	0.001 m^3⟨primary⟩
    5 ft to m	1.524 m⟨primary⟩
    log10 4	≈ ⟨secondary⟩0.6020599913⟨primary⟩
    log 4	≈ ⟨secondary⟩0.6020599913⟨primary⟩
    0!	1⟨primary⟩
    1!	1⟨primary⟩
    2!	2⟨primary⟩
    3!	6⟨primary⟩
    4!	24⟨primary⟩
    5!	120⟨primary⟩
    6!	720⟨primary⟩
    7!	5,040⟨primary⟩
    8!	40,320⟨primary⟩
    floor(3)	3⟨primary⟩
    floor(3.9)	3⟨primary⟩
    floor(-3)	-3⟨primary⟩
    floor(-3.1)	-4⟨primary⟩
    ceil(3)	3⟨primary⟩
    ceil(3.3)	4⟨primary⟩
    ceil(-3)	-3⟨primary⟩
    ceil(-3.3)	-3⟨primary⟩
    round(3)	3⟨primary⟩
    round(3.3)	3⟨primary⟩
    round(3.7)	4⟨primary⟩
    round(-3.3)	-3⟨primary⟩
    round(-3.7)	-4⟨primary⟩
    9/11 to float	0.(81)⟨primary⟩
    6#1 / 11 to float	6#0.(0313452421)⟨primary⟩
    6#0 + 6#1 / 7 to float	6#0.(05)⟨primary⟩
    0.25 as fraction	1/4⟨primary⟩
    0.21 as 1 dp	≈ ⟨secondary⟩0.2⟨primary⟩
    0.21 to 1 dp to auto	0.21⟨primary⟩
    502938/700 to float	718.48(285714)⟨primary⟩
    abs	abs⟨primary⟩
    sin	sin⟨primary⟩
    cos	cos⟨primary⟩
    tan	tan⟨primary⟩
    asin	asin⟨primary⟩
    acos	acos⟨primary⟩
    atan	atan⟨primary⟩
    sinh	sinh⟨primary⟩
    cosh	cosh⟨primary⟩
    tanh	tanh⟨primary⟩
    asinh	asinh⟨primary⟩
    acosh	acosh⟨primary⟩
    atanh	atanh⟨primary⟩
    ln	ln⟨primary⟩
    log2	log2⟨primary⟩
    log10	log10⟨primary⟩
    log	log10⟨primary⟩
    sin 0	0⟨primary⟩
    sin 1	≈ ⟨secondary⟩0.8414709848⟨primary⟩
    sin (1%)	≈ ⟨secondary⟩0.0099998333⟨primary⟩
    atan (1%)	≈ ⟨secondary⟩0.0099996667⟨primary⟩
    sin pi	0⟨primary⟩
    sin (2pi)	0⟨primary⟩
    sin (-pi)	0⟨primary⟩
    sin (-1000pi)	0⟨primary⟩
    sin (pi/2)	1⟨primary⟩
    sin (3pi/2)	-1⟨primary⟩
    sin (5pi/2)	1⟨primary⟩
    sin (7pi/2)	-1⟨primary⟩
    sin (-pi/2)	-1⟨primary⟩
    sin (-3pi/2)	1⟨primary⟩
    sin (-5pi/2)	-1⟨primary⟩
    sin (-7pi/2)	1⟨primary⟩
    sin (-1023pi/2)	1⟨primary⟩
    sin (pi/6)	0.5⟨primary⟩
    sin (5pi/6)	0.5⟨primary⟩
    sin (7pi/6)	-0.5⟨primary⟩
    sin (11pi/6)	-0.5⟨primary⟩
    sin (-pi/6)	-0.5⟨primary⟩
    sin (-5pi/6)	-0.5⟨primary⟩
    sin (-7pi/6)	0.5⟨primary⟩
    sin (-11pi/6)	0.5⟨primary⟩
    sin (180°)	0⟨primary⟩
    sin (30°)	0.5⟨primary⟩
    sin (1°)	≈ ⟨secondary⟩0.0174524064⟨primary⟩
    cos 0	1⟨primary⟩
    cos 1	≈ ⟨secondary⟩0.5403023059⟨primary⟩
    cos pi	-1⟨primary⟩
    cos (2pi)	1⟨primary⟩
    cos (-pi)	-1⟨primary⟩
    cos (-1000pi)	1⟨primary⟩
    cos (pi/2)	0⟨primary⟩
    cos (3pi/2)	0⟨primary⟩
    cos (5pi/2)	0⟨primary⟩
    cos (7pi/2)	0⟨primary⟩
    cos (-pi/2)	0⟨primary⟩
    cos (-3pi/2)	0⟨primary⟩
    cos (-5pi/2)	0⟨primary⟩
    cos (-7pi/2)	0⟨primary⟩
    cos (-1023pi/2)	0⟨primary⟩
    cos (pi/3)	0.5⟨primary⟩
    cos (2pi/3)	-0.5⟨primary⟩
    cos (4pi/3)	-0.5⟨primary⟩
    cos (5pi/3)	0.5⟨primary⟩
    cos (-pi/3)	0.5⟨primary⟩
    cos (-2pi/3)	-0.5⟨primary⟩
    cos (-4pi/3)	-0.5⟨primary⟩
    cos (-5pi/3)	0.5⟨primary⟩
    tau	≈ ⟨secondary⟩6.2831853072⟨primary⟩
    sin (tau / 2)	0⟨primary⟩
    π	≈ ⟨secondary⟩3.1415926536⟨primary⟩
    τ	≈ ⟨secondary⟩6.2831853072⟨primary⟩
    tan 0	0⟨primary⟩
    tan pi	0⟨primary⟩
    tan (2pi)	0⟨primary⟩
    asin 1	≈ ⟨secondary⟩1.5707963268⟨primary⟩
    asin 3	≈ ⟨secondary⟩1.5707963268 - 1.762747174i⟨primary⟩
    asin (-3)	≈ ⟨secondary⟩-1.5707963268 + 1.762747174i⟨primary⟩
    asin 1.01	≈ ⟨secondary⟩1.5707963268 - 0.1413037695i⟨primary⟩
    asin (-1.01)	≈ ⟨secondary⟩-1.5707963268 + 0.1413037695i⟨primary⟩
    acos 0	≈ ⟨secondary⟩1.5707963268⟨primary⟩
    acos 3	≈ ⟨secondary⟩0 ,+ 1.762747174i⟨primary⟩
    acos (-3)	≈ ⟨secondary⟩3.1415926536 - 1.762747174i⟨primary⟩
    acos 1.01	≈ ⟨secondary⟩0 ,+ 0.1413037695i⟨primary⟩
    acos (-1.01)	≈ ⟨secondary⟩3.1415926536 - 0.1413037695i⟨primary⟩
    acos 1	≈ ⟨secondary⟩0⟨primary⟩
    acos (-1)	≈ ⟨secondary⟩3.1415926536⟨primary⟩
    atan 1	≈ ⟨secondary⟩0.7853981634⟨primary⟩
    sinh 0	≈ ⟨secondary⟩0⟨primary⟩
    cosh 0	≈ ⟨secondary⟩1⟨primary⟩
    tanh 0	≈ ⟨secondary⟩0⟨primary⟩
    asinh 0	≈ ⟨secondary⟩0⟨primary⟩
    acosh 0	≈ ⟨secondary⟩1.5707963268i⟨primary⟩
    acosh 2	≈ ⟨secondary⟩1.3169578969⟨primary⟩
    atanh 0	≈ ⟨secondary⟩0⟨primary⟩
    atanh 3	≈ ⟨secondary⟩0.3465735903 + 1.5707963268i⟨primary⟩
    atanh (-3)	≈ ⟨secondary⟩-0.3465735903 + 1.5707963268i⟨primary⟩
    atanh 1.01	≈ ⟨secondary⟩2.651652454 + 1.5707963268i⟨primary⟩
    atanh (-1.01)	≈ ⟨secondary⟩-2.651652454 + 1.5707963268i⟨primary⟩
    ln 2	≈ ⟨secondary⟩0.6931471806⟨primary⟩
    exp 2	≈ ⟨secondary⟩7.3890560989⟨primary⟩
    log10 100	≈ ⟨secondary⟩2⟨primary⟩
    log10 1000	≈ ⟨secondary⟩3⟨primary⟩
    log10 10000	≈ ⟨secondary⟩4.0000000000⟨primary⟩
    log10 100000	≈ ⟨secondary⟩5⟨primary⟩
    log 100	≈ ⟨secondary⟩2⟨primary⟩
    log 1000	≈ ⟨secondary⟩3⟨primary⟩
    log 10000	≈ ⟨secondary⟩4.0000000000⟨primary⟩
    log 100000	≈ ⟨secondary⟩5⟨primary⟩
    log2 65536	≈ ⟨secondary⟩16⟨primary⟩
    log2(2^2048)	≈ ⟨secondary⟩2,048⟨primary⟩
    log2(3*2^2048)	≈ ⟨secondary⟩2,049.5849625007⟨primary⟩
    log10 (-1)	≈ ⟨secondary⟩1.3643763538i⟨primary⟩
    log2 (-1)	≈ ⟨secondary⟩4.5323601418i⟨primary⟩
    sqrt(-2)	≈ ⟨secondary⟩0 ,+ 1.4142135624i⟨primary⟩
    (-2)^3	-8⟨primary⟩
    (-2)^5	-32⟨primary⟩
    2^-2	0.25⟨primary⟩
    (-2)^-2	0.25⟨primary⟩
    (-2)^-3	-0.125⟨primary⟩
    (-2)^-4	0.0625⟨primary⟩
    ln	ln⟨primary⟩
    sqrt i	≈ ⟨secondary⟩0.7071067812 + 0.7071067812i⟨primary⟩
    sqrt (-2i)	≈ ⟨secondary⟩1.0000000000 - 1.0000000000i⟨primary⟩
    cbrt i	≈ ⟨secondary⟩0.8660254038 + 0.5000000000i⟨primary⟩
    cbrt (-2i)	≈ ⟨secondary⟩1.0911236360 - 0.6299605249i⟨primary⟩
    sin i	≈ ⟨secondary⟩1.1752011936i⟨primary⟩
    cos i	≈ ⟨secondary⟩1.5430806348⟨primary⟩
    tan i	≈ ⟨secondary⟩0.7615941560i⟨primary⟩
    ln i	≈ ⟨secondary⟩1.5707963268i⟨primary⟩
    log2 i	≈ ⟨secondary⟩2.2661800709i⟨primary⟩
    log10 i	≈ ⟨secondary⟩0.6821881769i⟨primary⟩
    1 Hz + /s	2 Hz⟨primary⟩
    (b: 5 + b) 1	6⟨primary⟩
    (addFive: 4)(b: 5 + b)	4⟨primary⟩
    (\\x.\\y.x)1 2	1⟨primary⟩
    kg^pi	1 kg^π⟨primary⟩
    kg^(2pi) / kg^(2pi) to 1	1⟨primary⟩
    cis 0	1⟨primary⟩
    cis (pi/2)	i⟨primary⟩
    cis (3pi/2)	-i⟨primary⟩
    cis (2pi)	1⟨primary⟩
    cis -(2pi)	1⟨primary⟩
    cis (pi/6)	≈ ⟨secondary⟩0.8660254038 + 0.5i⟨primary⟩
    1/sin	\\x.(1/(sin x))⟨secondary⟩
    1234567.55645 to 1 sf	≈ ⟨secondary⟩1,000,000⟨primary⟩
    1234567.55645 to 2 sf	≈ ⟨secondary⟩1,200,000⟨primary⟩
    1234567.55645 to 3 sf	≈ ⟨secondary⟩1,230,000⟨primary⟩
    1234567.55645 to 4 sf	≈ ⟨secondary⟩1,234,000⟨primary⟩
    1234567.55645 to 5 sf	≈ ⟨secondary⟩1,234,500⟨primary⟩
    1234567.55645 to 6 sf	≈ ⟨secondary⟩1,234,560⟨primary⟩
    1234567.55645 to 7 sf	≈ ⟨secondary⟩1,234,568⟨primary⟩
    1234567.55645 to 8 sf	≈ ⟨secondary⟩1,234,567.6⟨primary⟩
    1234567.55645 to 9 sf	≈ ⟨secondary⟩1,234,567.56⟨primary⟩
    1234567.55645 to 10 sf	≈ ⟨secondary⟩1,234,567.556⟨primary⟩
    1234567.55645 to 11 sf	≈ ⟨secondary⟩1,234,567.5565⟨primary⟩
    1234567.55645 to 12 sf	1,234,567.55645⟨primary⟩
    1234567.55645 to 13 sf	1,234,567.55645⟨primary⟩
    pi / 1000000 to 1 sf	≈ ⟨secondary⟩0.000003⟨primary⟩
    pi / 1000000 to 2 sf	≈ ⟨secondary⟩0.0000031⟨primary⟩
    123.9 to 3 sf	≈ ⟨secondary⟩124⟨primary⟩
    0.00555 to 2 sf	≈ ⟨secondary⟩0.0056⟨primary⟩
    pi / 1000000 to 3 sf	≈ ⟨secondary⟩0.00000314⟨primary⟩
    pi / 1000000 to 4 sf	≈ ⟨secondary⟩0.000003142⟨primary⟩
    pi / 1000000 to 5 sf	≈ ⟨secondary⟩0.0000031416⟨primary⟩
    pi / 1000000 to 6 sf	≈ ⟨secondary⟩0.00000314159⟨primary⟩
    pi / 1000000 to 7 sf	≈ ⟨secondary⟩0.000003141593⟨primary⟩
    pi / 1000000 to 8 sf	≈ ⟨secondary⟩0.0000031415927⟨primary⟩
    pi / 1000000 to 9 sf	≈ ⟨secondary⟩0.00000314159265⟨primary⟩
    pi / 1000000 to 10 sf	≈ ⟨secondary⟩0.000003141592654⟨primary⟩
    pi / 1000000 to 11 sf	≈ ⟨secondary⟩0.0000031415926536⟨primary⟩
    1e6 pi to 1 sf	≈ ⟨secondary⟩3,000,000⟨primary⟩
    1e6 pi to 2 sf	≈ ⟨secondary⟩3,100,000⟨primary⟩
    1e6 pi to 3 sf	≈ ⟨secondary⟩3,140,000⟨primary⟩
    1e6 pi to 4 sf	≈ ⟨secondary⟩3,141,000⟨primary⟩
    1e6 pi to 5 sf	≈ ⟨secondary⟩3,141,500⟨primary⟩
    1e6 pi to 6 sf	≈ ⟨secondary⟩3,141,590⟨primary⟩
    1e6 pi to 7 sf	≈ ⟨secondary⟩3,141,593⟨primary⟩
    1e6 pi to 8 sf	≈ ⟨secondary⟩3,141,592.7⟨primary⟩
    1e6 pi to 9 sf	≈ ⟨secondary⟩3,141,592.65⟨primary⟩
    1e6 pi to 10 sf	≈ ⟨secondary⟩3,141,592.654⟨primary⟩
    1234567 to 1 sf	≈ ⟨secondary⟩1,000,000⟨primary⟩
    1234567 to 2 sf	≈ ⟨secondary⟩1,200,000⟨primary⟩
    1234567 to 3 sf	≈ ⟨secondary⟩1,230,000⟨primary⟩
    1234567 to 4 sf	≈ ⟨secondary⟩1,234,000⟨primary⟩
    1234567 to 5 sf	≈ ⟨secondary⟩1,234,500⟨primary⟩
    1234567 to 6 sf	≈ ⟨secondary⟩1,234,560⟨primary⟩
    1234567 to 7 sf	1,234,567⟨primary⟩
    1234567 to 8 sf	1,234,567⟨primary⟩
    1234567 to 9 sf	1,234,567⟨primary⟩
    1234567 to 10 sf	1,234,567⟨primary⟩
    1234560 to 5sf	≈ ⟨secondary⟩1,234,500⟨primary⟩
    1234560 to 6sf	1,234,560⟨primary⟩
    1234560 to 7sf	1,234,560⟨primary⟩
    1234560.1 to 6sf	≈ ⟨secondary⟩1,234,560⟨primary⟩
    12345601 to 6sf	≈ ⟨secondary⟩12,345,600⟨primary⟩
    12345601 to 7sf	≈ ⟨secondary⟩12,345,600⟨primary⟩
    12345601 to 8sf	12,345,601⟨primary⟩
    100 kWh/yr to watt	≈ ⟨secondary⟩11.4079552707 watts⟨primary⟩
    3 square feet to square meters	0.27870912 meters^2⟨primary⟩
    1 yard lb to hex to kg m to 3sf	≈ ⟨secondary⟩0,.6A3₁₆ kg m⟨primary⟩
    i yard lb to hex to kg m to 3sf	≈ ⟨secondary⟩0.,6A3I₁₆ kg m⟨primary⟩
    1000000000 to billion	1 billion⟨primary⟩
    640 acre to mi^2	1 mi^2⟨primary⟩
    1 mile^2 to acre	640 acres⟨primary⟩
    1 hectare to km^2	0.01 km^2⟨primary⟩
    2 km^2 to hectare	200 hectares⟨primary⟩
    1% to unitless	0.01⟨primary⟩
    0.18mL * 40 mg/mL	7.2 mg⟨primary⟩
    kg g^0	1 kg⟨primary⟩
    kg g^-1	1,000⟨primary⟩
    kg^2 g	0.001 kg^3⟨primary⟩
    kg^2 g^0	1 kg^2⟨primary⟩
    kg^2 g^-1	1,000 kg⟨primary⟩
    kg^2 g^-2	1,000,000⟨primary⟩
    escape_velocity of earth / gravity of earth	≈ ⟨secondary⟩1,140.6545558371 s⟨primary⟩
    273K to °R	491.4 °R⟨primary⟩
    1J/K to J/°C	1 J/°C⟨primary⟩
    1K+1°C	2 K⟨primary⟩
    1K+1°F	≈ ⟨secondary⟩1.5555555556 K⟨primary⟩
    1°C+1K	2 °C⟨primary⟩
    1°F+1K	2.8 °F⟨primary⟩
    1°C+1°F	≈ ⟨secondary⟩1.5555555556 °C⟨primary⟩
    1°C+1°R	≈ ⟨secondary⟩1.5555555556 °C⟨primary⟩
    1°F+1°C	2.8 °F⟨primary⟩
    1°F+10kK	18,001 °F⟨primary⟩
    -273.15°C+1mK	-,273.149 °C⟨primary⟩
    1J/K to J/°F	≈ ⟨secondary⟩0.5555555556 J/°F⟨primary⟩
    0°C to K	273.15 K⟨primary⟩
    6°K	6 K⟨primary⟩
    (1°F)^2 + 1 K^2	4.24 °F^2⟨primary⟩
    (1°F)^2 to 1 K^2	≈ ⟨secondary⟩0.3086419753 K^2⟨primary⟩
    100°C to °F	212 °F⟨primary⟩
    0°C to °F	32 °F⟨primary⟩
    0K to °F	-,459.67 °F⟨primary⟩
    0 millicelsius to °F	32 °F⟨primary⟩
    0 kilocelsius to °F	32 °F⟨primary⟩
    0 kilocelsius to millifahrenheit	32,000 millifahrenheit⟨primary⟩
    5°C to °F	41 °F⟨primary⟩
    15°C to °R	518.67 °R⟨primary⟩
    15°C to K	288.15 K⟨primary⟩
    4C	4 °C⟨primary⟩
    4C to F	39.2 °F⟨primary⟩
    pi radians to °	180°⟨primary⟩
    -40 F to C	-40 °C⟨primary⟩
    25Gib/s to GB/s	3.3554432 GB/s⟨primary⟩
    1 + 1	2⟨primary⟩
    cis 4	≈ ⟨secondary⟩-0.6536436209 - 0.7568024953i⟨primary⟩
    '\\^A'	\x01⟨primary⟩
    '\\^B'	\x02⟨primary⟩
    '\\^C'	\x03⟨primary⟩
    '\\^D'	\x04⟨primary⟩
    '\\^E'	\x05⟨primary⟩
    '\\^F'	\x06⟨primary⟩
    '\\^G'	\x07⟨primary⟩
    '\\^H'	\x08⟨primary⟩
    '\\^I'	\t⟨primary⟩
    '\\^J'	\n⟨primary⟩
    '\\^K'	\x0b⟨primary⟩
    '\\^L'	\x0c⟨primary⟩
    '\\^P'	\x10⟨primary⟩
    '\\^X'	\x18⟨primary⟩
    '\\^Y'	\x19⟨primary⟩
    '\\^Z'	\x1a⟨primary⟩
    '\\u{7e}'	~⟨primary⟩
    '\\u{69}'	i⟨primary⟩
    '\\u{5437}'	吷⟨primary⟩
    '\\u{10ffff}'	􏿿⟨primary⟩
    acre foot to m^3	1,233.48183754752 m^3⟨primary⟩
    2.54cm to "	1"⟨primary⟩
    30.48cm to '	1'⟨primary⟩
    30.48cm to ' # converting cm to feet	1'⟨primary⟩
    30.48cm to ' # converting cm to feet\n	1'⟨primary⟩
    30.48cm to # converting cm\n feet # to feet	1 foot⟨primary⟩
    30.48cm to # converting cm\n ' # to feet	1'⟨primary⟩
    4% + 3‰	4.3%⟨primary⟩
    5 'tests'	5 tests⟨primary⟩
    5 'pigeons' per meter	5 pigeons/meter⟨primary⟩
    asin -1.1	≈ ⟨secondary⟩-1.5707963268 + 0.4435682544i⟨primary⟩
    15*3*50/1000 'cases'	2.25 cases⟨primary⟩
    ms/year	≈ ⟨secondary⟩0⟨primary⟩
    1.550519768*10^-8 to ms/year	≈ ⟨secondary⟩489.2963754105153 ms/year⟨primary⟩
    5 − 2 ✕ 3 × 1 ÷ 1 ∕ 3	3⟨primary⟩
    0 to bool	false⟨primary⟩
    0 to boolean	false⟨primary⟩
    1 to bool	true⟨primary⟩
    -1 to bool	true⟨primary⟩
    5 sqm	5 m^2⟨primary⟩
    5 sqft	5 ft^2⟨primary⟩
    0b1001010 mod 5	100₂⟨primary⟩
    9283749283460298374027364928736492873469287354267354 mod 4	2⟨primary⟩
    month of ('2020-03-04' to date)	March⟨primary⟩
    day_of_week of ('2020-05-08' to date)	Friday⟨primary⟩
    2; 4	4⟨primary⟩
    4/3 to mixed_frac	1 ,1/3⟨primary⟩
    1 farad to A^2 kg^-1 m^-2 s^4	1 A^2 s^4 kg^-1 m^-2⟨primary⟩
    1234;	1,234⟨primary⟩
    ;432	432⟨primary⟩
    ;;3	3⟨primary⟩
    34;;;	34⟨primary⟩
    ('2020-05-04' to date) + 500 days	Thursday, 16 September 2021⟨primary⟩
    (λx.x) 5	5⟨primary⟩
    25146 kmh to mph	15,625 mph⟨primary⟩
    25146 km/h to mph	15,625 mph⟨primary⟩
    5'1 to m to 2dp	≈ ⟨secondary⟩1.55 m⟨primary⟩
    0'1 to m to 2dp	≈ ⟨secondary⟩0.03 m⟨primary⟩
    5'1 + 5m	≈ ⟨secondary⟩21.4875328084'⟨primary⟩
    5 coulomb to mC	5,000 mC⟨primary⟩
    5 farad to mF	5,000 mF⟨primary⟩
    0.5 points to mm	≈ ⟨secondary⟩0.1763888889 mm⟨primary⟩
    10 RPM to rad/s	≈ ⟨secondary⟩1.0471975512 rad/s⟨primary⟩
    6 foot 4 in cm	193.04 cm⟨primary⟩
    log10 (1m / (1m	≈ ⟨secondary⟩0⟨primary⟩
    #!/usr/bin/env fend\n1 + 1	2⟨primary⟩
    0 & 0	0⟨primary⟩
    0 & 1	0⟨primary⟩
    1 & 0	0⟨primary⟩
    1 & 1	1⟨primary⟩
    0 & 91802367489176234987162938461829374691238641	0⟨primary⟩
    912834710927364108273648927346788234682764 &\n        98123740918263740896274873648273642342534252	≈ ⟨secondary⟩2.07742387⟨primary⟩ × ⟨secondary⟩10⁴¹⟨primary⟩
    0 | 0	0⟨primary⟩
    0 | 1	1⟨primary⟩
    1 | 0	1⟨primary⟩
    1 | 1	1⟨primary⟩
    3 | 4	7⟨primary⟩
    255 | 34	255⟨primary⟩
    0b0011 | 0b0101	111₂⟨primary⟩
    0 xor 0	0⟨primary⟩
    0 xor 1	1⟨primary⟩
    1 xor 0	1⟨primary⟩
    1 xor 1	0⟨primary⟩
    019278364182374698123476928376459726354982 xor\n\t\t387294658347659283475689347659823745692837465	≈ ⟨secondary⟩3.872862753⟨primary⟩ × ⟨secondary⟩10⁴⁴⟨primary⟩
    0 << 10	0⟨primary⟩
    54 << 1	108⟨primary⟩
    54 << 2	216⟨primary⟩
    54 << 3	432⟨primary⟩
    54 >> 12	0⟨primary⟩
    54 >> 1	27⟨primary⟩
    54 >> 2	13⟨primary⟩
    54 >> 3	6⟨primary⟩
    54 << 1 & 54 >> 1	8⟨primary⟩
    5 nCr 2	10⟨primary⟩
    5 choose 2	10⟨primary⟩
    10 nCr 3	120⟨primary⟩
    10 choose 3	120⟨primary⟩
    5 nPr 2	20⟨primary⟩
    5 permute 2	20⟨primary⟩
    10 nPr 3	720⟨primary⟩
    10 permute 3	720⟨primary⟩
    @1970-01-01	Thursday, 1 January 1970⟨primary⟩
    @2022-11-29 - 2 days	Sunday, 27 November 2022⟨primary⟩
    @2022-11-29 - 2 weeks	Tuesday, 15 November 2022⟨primary⟩
    @2022-11-29 - 2 months	Thursday, 29 September 2022⟨primary⟩
    @2022-11-29 - 2 years	Sunday, 29 November 2020⟨primary⟩
    @2022-03-01 - 1 month	Tuesday, 1 February 2022⟨primary⟩
    @2020-02-28 - 1 year	Thursday, 28 February 2019⟨primary⟩
    @2020-08-01 - 1 year	Thursday, 1 August 2019⟨primary⟩
    atan((30 centi meter) / (2 meter))	≈ ⟨secondary⟩0.1488899476⟨primary⟩
    atan((30 centimeter) / (2 meter))	≈ ⟨secondary⟩0.1488899476⟨primary⟩
    light_year / light to days	365.25 days⟨primary⟩
    light year / light to days	365.25 days⟨primary⟩
    lightyear / light to days	365.25 days⟨primary⟩
    light day / light to days	1 day⟨primary⟩
    2 thou to mm	0.0508 mm⟨primary⟩
    70 km s^-1 Mpc^-1 to 25dp	≈ ⟨secondary⟩2.2685455⟨primary⟩ × ⟨secondary⟩10⁻¹⁸ s^-1⟨primary⟩
    5 oC	5 °C⟨primary⟩
    5 to million	0.000005 million⟨primary⟩
    (5 volts) / (2 ohms)	2.5 amperes⟨primary⟩
    c/(145MHz)	≈ ⟨secondary⟩2.0675341931 meters⟨primary⟩
    4556 ohm * ampere	4,556 volts⟨primary⟩
    4556 volt / ampere	4,556 ohms⟨primary⟩
    200²	40,000⟨primary⟩
    13¹³ days	302,875,106,592,253 days⟨primary⟩
    1 + 2 ≠ 4	true⟨primary⟩
    1 + 2 <> 4	true⟨primary⟩
    1 to roman	I⟨primary⟩
    2 to roman	II⟨primary⟩
    3 to roman	III⟨primary⟩
    4 to roman	IV⟨primary⟩
    5 to roman	V⟨primary⟩
    6 to roman	VI⟨primary⟩
    7 to roman	VII⟨primary⟩
    8 to roman	VIII⟨primary⟩
    9 to roman	IX⟨primary⟩
    10 to roman	X⟨primary⟩
    11 to roman	XI⟨primary⟩
    12 to roman	XII⟨primary⟩
    13 to roman	XIII⟨primary⟩
    14 to roman	XIV⟨primary⟩
    15 to roman	XV⟨primary⟩
    16 to roman	XVI⟨primary⟩
    17 to roman	XVII⟨primary⟩
    18 to roman	XVIII⟨primary⟩
    19 to roman	XIX⟨primary⟩
    20 to roman	XX⟨primary⟩
    21 to roman	XXI⟨primary⟩
    22 to roman	XXII⟨primary⟩
    45 to roman	XLV⟨primary⟩
    134 to roman	CXXXIV⟨primary⟩
    1965 to roman	MCMLXV⟨primary⟩
    2020 to roman	MMXX⟨primary⟩
    3456 to roman	MMMCDLVI⟨primary⟩
    1452 to roman	MCDLII⟨primary⟩
    20002 to roman	X̅X̅II⟨primary⟩
    4U to cm	17.78 cm⟨primary⟩
    5%4	1⟨primary⟩
    (104857566-103811072+1) % (1024*1024/512)	2,015⟨primary⟩
    5 mod (4k)	5⟨primary⟩
    (4k)^2	16,000,000⟨primary⟩
    fib 0	0⟨primary⟩
    fib 1	1⟨primary⟩
    fib 2	1⟨primary⟩
    fib 3	2⟨primary⟩
    fib 4	3⟨primary⟩
    fib 5	5⟨primary⟩
    fib 6	8⟨primary⟩
    fib 7	13⟨primary⟩
    fib 8	21⟨primary⟩
    fib 9	34⟨primary⟩
    fib 10	55⟨primary⟩
    fib 11	89⟨primary⟩
    SIN PI	0⟨primary⟩
    COS TAU	1⟨primary⟩
    LOG 1	≈ ⟨secondary⟩0⟨primary⟩
    LOG10 1	≈ ⟨secondary⟩0⟨primary⟩
    EXP 0	≈ ⟨secondary⟩1⟨primary⟩
    1 to words	one⟨primary⟩
    9 to words	nine⟨primary⟩
    15 to words	fifteen⟨primary⟩
    20 to words	twenty⟨primary⟩
    99 to words	ninety-nine⟨primary⟩
    154 to words	one hundred and fifty-four⟨primary⟩
    500 to words	five hundred⟨primary⟩
    999 to words	nine hundred and ninety-nine⟨primary⟩
    1000 to words	one thousand⟨primary⟩
    4321 to words	four thousand three hundred and twenty-one⟨primary⟩
    1000000 to words	one million⟨primary⟩
    1234567 to words	one million two hundred and thirty-four thousand five hundred and sixty-seven⟨primary⟩
    1000000000 to words	one billion⟨primary⟩
    9876543210 to words	nine billion eight hundred and seventy-six million five hundred and forty-three thousand two hundred and ten⟨primary⟩
    1000000000000 to words	one trillion⟨primary⟩
    1234567890123456 to words	one quadrillion two hundred and thirty-four trillion five hundred and sixty-seven billion eight hundred and ninety million one hundred and twenty-three thousand four hundred and fifty-six⟨primary⟩
    1000000000000000000000 to words	one sextillion⟨primary⟩
    1000000000000000000000000 to words	one septillion⟨primary⟩
    4m + 0	4 m⟨primary⟩
    4m + 0kg	4 m⟨primary⟩
    4m + (sin pi) kg	4 m⟨primary⟩
    kilopond to N	9.80665 N⟨primary⟩
    megapond to N	9,806.65 N⟨primary⟩
    gf to N	0.00980665 N⟨primary⟩
    """##
}
