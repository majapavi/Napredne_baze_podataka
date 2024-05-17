
ZADATAK 1:

select ime_igrac, prezime_igrac from igrac

inner join igrac_klub on igrac.sif_igrac = igrac_klub.sif_igrac
inner join klub on klub.sif_klub = igrac_klub.sif_klub

where igrac_klub.godina = 2019
and klub.naziv_klub = 'OK Kaštela'

order by igrac.prezime_igrac, igrac.ime_igrac;


Matea	Ćurak
Ema		Kurtović
Marija	Ljulj
Dora	Matas
Jelena	Ninčević
Tonka	Parčina
Ivana	Prkačin
Ana		Rimac
Nika	Stanović
Marija	Sudar
Tea		Vranković
Elena	Vukić

-----------------------------------------------------------------------------------

ZADATAK 2:

select naziv_klub, godina from igrac_klub

inner join klub on igrac_klub.sif_klub = klub.sif_klub

where igrac_klub.sif_igrac =
      (select sif_igrac from igrac
	  where ime_igrac = 'Jurica' and prezime_igrac = 'Šućur')

order by igrac_klub.godina desc;


OK Split			2022
OK Split			2021
MOK Mursa - Osijek	2020
MOK Mursa - Osijek	2019
MOK Mursa - Osijek	2018

-----------------------------------------------------------------------------------

ZADATAK 3:

select ime_igrac, prezime_igrac, statistika.blokovi, statistika.godina from statistika

inner join igrac on statistika.sif_igrac = igrac.sif_igrac

where statistika.blokovi > 90;


Božana		Butigan		97	2018
Benjamin	Daca		91	2022

-----------------------------------------------------------------------------------

ZADATAK 4:

select sezona.sezona, max(statistika.bodovi) from statistika

inner join klub on statistika.sif_klub = klub.sif_klub
inner join sezona on statistika.godina = sezona.godina

where klub.m_z = 'm'
group by sezona.sezona;


2018/19	426
2019/20	336
2020/21	509
2021/22	468
2022/23	412

-----------------------------------------------------------------------------------

ZADATAK 5:

select distinct klub.naziv_klub from statistika

inner join klub on statistika.sif_klub = klub.sif_klub

where klub.m_z = 'z'
and statistika.godina = 2020;


HAOK Mladost
HAOK Rijeka CO
OK Brda
OK Dinamo
OK Kaštela
OK Marina Kaštela
OK Olimpik
OK Poreč
OK Split
OK Veli Vrh
ŽOK Dubrovnik
ŽOK Enna Vukovar
ŽOK Osijek
