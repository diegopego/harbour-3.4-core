/*
 * TIP Class oriented Internet protocol library
 *
 * Copyright 2003 Giancarlo Niccolai <gian@niccolai.ws>
 * Copyright 2007 Hannes Ziegler (INetErrorDesc(), lastErrorCode(), lastErrorMessage())
 * Copyright 2007 Toninho@fwi (::nWrite to work like ::nRead)
 * Copyright 2009 Luiz Rafael Culik (luiz at xharbour dot com dot br) (Proxy connection)
 * Copyright 2009 Viktor Szakats (vszakats.net/harbour) (SSL support)
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.txt.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA (or visit the web site https://www.gnu.org/).
 *
 * As a special exception, the Harbour Project gives permission for
 * additional uses of the text contained in its release of Harbour.
 *
 * The exception is that, if you link the Harbour libraries with other
 * files to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the Harbour library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the Harbour
 * Project under the name Harbour.  If you copy code from other
 * Harbour Project or Free Software Foundation releases into a copy of
 * Harbour, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for Harbour, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.
 *
 */

#include "hbclass.ch"

#include "error.ch"
#include "fileio.ch"

#if defined( _SSL_DEBUG_TEMP )
   #include "simpleio.ch"
#endif

#include "hbssl.ch"
#include "hbssl.hbx"

#define RCV_BUF_SIZE  Int( ::InetRcvBufSize( ::SocketCon ) / 2 )
#define SND_BUF_SIZE  Int( ::InetSndBufSize( ::SocketCon ) / 2 )

/* Inet Client class */

CREATE CLASS TIPClient

   CLASS VAR bInitSocks  INIT .F.
   CLASS VAR cCRLF       INIT e"\r\n"

   VAR oUrl                      /* url to wich to connect */
   VAR oCredentials              /* credential needed to access the service */
   VAR nStatus           INIT 0  /* basic status */
   VAR SocketCon
   VAR bTrace

   VAR nDefaultRcvBuffSize
   VAR nDefaultSndBuffSize

   VAR nLength           INIT -1 /* Input stream length */
   VAR nRead             INIT 0  /* Input stream data read by the app*/
   VAR nLastRead         INIT 0  /* Last physical read amount */

   VAR nDefaultPort
   VAR nConnTimeout
   VAR bInitialized      INIT .F.

   VAR cReply
   VAR nAccessMode
   VAR nWrite            INIT 0
   VAR nLastWrite        INIT 0

   VAR bEof              INIT .F.
   VAR isOpen            INIT .F.

   VAR exGauge              /* Gauge control; it can be a codeblock or a function pointer. */

   VAR lTLS              INIT .F.

   VAR lHasSSL           INIT tip_SSL()
   VAR ssl_ctx
   VAR ssl
   VAR nSSLError         INIT 0

   VAR Cargo

   /* Data for proxy connection */
   VAR cProxyHost
   VAR nProxyPort        INIT 0
   VAR cProxyUser
   VAR cProxyPassword

   METHOD New( oUrl, xTrace, oCredentials )
   METHOD Open( cUrl )

   METHOD EnableTLS( lEnable )

   METHOD Read( nLen )
   METHOD ReadToFile( cFile, nMode, nSize )
   METHOD Write( cData, nLen, lCommit )
   METHOD Commit()
   METHOD WriteFromFile( cFile )
   METHOD Reset()
   METHOD Close()

   METHOD SetProxy( cProxyHost, nProxyPort, cProxyUser, cProxyPassword )

   METHOD lastErrorCode() INLINE ::nLastError
   METHOD lastErrorMessage( SocketCon ) INLINE ::inetErrorDesc( SocketCon )

   METHOD InetRcvBufSize( SocketCon, nSizeBuff )
   METHOD InetSndBufSize( SocketCon, nSizeBuff )

   METHOD InetTimeOut( SocketCon, nConnTimeout )

   METHOD HasSSL() INLINE ::lHasSSL

   PROTECTED:

   VAR nLastError INIT 0

   METHOD OpenProxy( cServer, nPort, cProxy, nProxyPort, cResp, cUserName, cPassword, cUserAgent )
   METHOD ReadHTTPProxyResponse( cResponse )

   /* Methods to log data if needed */
   METHOD inetRecv( SocketCon, cStr1, len )
   METHOD inetRecvLine( SocketCon, nRet, size )
   METHOD inetRecvAll( SocketCon, cRet, size )
   METHOD inetCount( SocketCon )
   METHOD inetSendAll( SocketCon, cData, nLen )
   METHOD inetErrorCode( SocketCon )
   METHOD inetErrorDesc( SocketCon )
   METHOD inetConnect( cServer, nPort, SocketCon )

   METHOD Log( ... )

ENDCLASS

METHOD New( oUrl, xTrace, oCredentials ) CLASS TIPClient

   LOCAL oErr
   LOCAL oLog

   LOCAL aProtoSSL := { "ftps", "https", "pop3s", "pops", "smtps" }

   DO CASE
   CASE HB_ISSTRING( xTrace ) .OR. hb_defaultValue( xTrace, .F. )
      oLog := TIPLog():New( iif( HB_ISSTRING( xTrace ), xTrace, NIL ) )
      ::bTrace := {| cMsg | iif( PCount() > 0, oLog:Add( cMsg ), oLog:Close() ) }
   CASE HB_ISEVALITEM( xTrace )
      ::bTrace := xTrace
   ENDCASE

   IF HB_ISSTRING( oUrl )
      oUrl := TUrl():New( oUrl )
   ENDIF

   IF hb_AScan( { "ftp", "http", "pop", "smtp" }, oURL:cProto,,, .T. ) == 0 .AND. ;
      ( ! ::lHasSSL .OR. hb_AScan( aProtoSSL, oURL:cProto,,, .T. ) == 0 )

      oErr := ErrorNew()
      oErr:Args          := { Self, oURL:cProto }
      oErr:CanDefault    := .F.
      oErr:CanRetry      := .F.
      oErr:CanSubstitute := .T.
      oErr:Description   := "unsupported protocol"
      oErr:GenCode       := EG_UNSUPPORTED
      oErr:Operation     := ::className() + ":new()"
      oErr:Severity      := ES_ERROR
      oErr:SubCode       := 1081
      oErr:SubSystem     := "BASE"
      Eval( ErrorBlock(), oErr )
   ENDIF

   IF ! ::bInitSocks
      hb_inetInit()
      IF ::lHasSSL
         SSL_init()
         RAND_seed( hb_randStr( 20 ) + hb_UserName() + hb_TToS( hb_DateTime() ) + NetName() )
      ENDIF
      ::bInitSocks := .T.
   ENDIF

   IF ::lHasSSL .AND. hb_AScan( aProtoSSL, oURL:cProto,,, .T. ) > 0
      ::EnableTLS( .T. )
   ENDIF

   ::oUrl         := oUrl
   ::oCredentials := oCredentials

   RETURN self

METHOD Open( cUrl ) CLASS TIPClient

   LOCAL nPort

   IF HB_ISSTRING( cUrl )
      ::oUrl := TUrl():New( cUrl )
   ENDIF

   nPort := iif( ::oUrl:nPort == -1, ::nDefaultPort, ::oUrl:nPort )

   ::SocketCon := hb_inetCreate()

   ::InetTimeOut( ::SocketCon )

   IF Empty( ::cProxyHost )
      ::inetConnect( ::oUrl:cServer, nPort, ::SocketCon )
      IF ::inetErrorCode( ::SocketCon ) != 0
         RETURN .F.
      ENDIF
   ELSEIF ! ::OpenProxy( ::oUrl:cServer, nPort, ::cProxyHost, ::nProxyPort,, ::cProxyUser, ::cProxyPassword, "Mozilla/3.0 compatible" )
      RETURN .F.
   ENDIF
   ::isOpen := .T.

   RETURN .T.

METHOD EnableTLS( lEnable ) CLASS TIPClient

   LOCAL lSuccess

   IF ::lTLS == lEnable
      RETURN .T.
   ENDIF

   IF lEnable
      IF ::lHasSSL
         ::ssl_ctx := SSL_CTX_new()
         ::ssl := SSL_new( ::ssl_ctx )
         ::lTLS := .T.
         lSuccess := .T.
      ELSE
         lSuccess := .F.
      ENDIF
   ELSE
      IF ::lHasSSL
         ::lTLS := .F.
         lSuccess := .T.
      ELSE
         lSuccess := .T.
      ENDIF
   ENDIF

   RETURN lSuccess

METHOD OpenProxy( cServer, nPort, cProxy, nProxyPort, cResp, cUserName, cPassword, cUserAgent ) CLASS TIPClient

   LOCAL cRequest
   LOCAL lRet := .F.
   LOCAL tmp

   ::inetConnect( cProxy, nProxyPort, ::SocketCon )

   IF ( tmp := ::inetErrorCode( ::SocketCon ) ) == 0
      cRequest := ;
         "CONNECT " + cServer + ":" + hb_ntos( nPort ) + " HTTP/1.1" + Chr( 13 ) + Chr( 10 ) + ;
         "Proxy-Connection: Keep-Alive" + Chr( 13 ) + Chr( 10 )
      IF HB_ISSTRING( cUserAgent ) .AND. ! Empty( cUserAgent )
         cRequest += "User-Agent: " + cUserAgent + Chr( 13 ) + Chr( 10 )
      ENDIF
      IF HB_ISSTRING( cUserName ) .AND. ! Empty( cUserName )
         cRequest += "Proxy-Authorization: Basic " + hb_base64Encode( cUserName + ":" + hb_defaultValue( cPassword, "" ) ) + Chr( 13 ) + Chr( 10 )
      ENDIF
      cRequest += Chr( 13 ) + Chr( 10 )
      ::inetSendAll( ::SocketCon, cRequest )
      cResp := ""
      IF ::ReadHTTPProxyResponse( @cResp ) .AND. ;
         ( tmp := At( " ", cResp ) ) > 0 .AND. ;
         Val( SubStr( cResp, tmp + 1 ) ) == 200
         lRet := .T.
      ENDIF
      IF ! lRet
         ::close()
      ENDIF
   ELSE
      cResp := hb_ntos( tmp )
   ENDIF

   RETURN lRet

METHOD ReadHTTPProxyResponse( /* @ */ cResponse ) CLASS TIPClient

   LOCAL bMoreDataToRead := .T.
   LOCAL nLength
   LOCAL cBuffer

   DO WHILE bMoreDataToRead

      cBuffer := Space( 1 )
      IF ::inetRecv( ::SocketCon, @cBuffer, hb_BLen( cBuffer ) ) <= 0
         RETURN .F.
      ENDIF
      cResponse += cBuffer

      IF ( nLength := hb_BLen( cResponse ) ) >= 4
         bMoreDataToRead := ;
            hb_BPeek( cResponse, nLength - 3 ) != 13 .OR. ;
            hb_BPeek( cResponse, nLength - 2 ) != 10 .OR. ;
            hb_BPeek( cResponse, nLength - 1 ) != 13 .OR. ;
            hb_BPeek( cResponse, nLength - 0 ) != 10
      ENDIF
   ENDDO

   RETURN .T.

METHOD Close() CLASS TIPClient

   LOCAL nRet

   IF Empty( ::SocketCon )
      nRet := -1
   ELSE
      nRet := hb_inetClose( ::SocketCon )

      IF ::lTLS .AND. ::lHasSSL
         SSL_shutdown( ::ssl )
         ::ssl := NIL
         ::ssl_ctx := NIL
      ENDIF

      ::SocketCon := NIL
      ::isOpen := .F.
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      /* Call with no parameter to signal end of logging session */
      Eval( ::bTrace )
   ENDIF

   RETURN nRet

METHOD Reset() CLASS TIPClient

   ::bInitialized := .F.
   ::bEof := .F.

   RETURN .T.

METHOD Commit() CLASS TIPClient
   RETURN .T.

METHOD Read( nLen ) CLASS TIPClient

   LOCAL cStr0
   LOCAL cStr1

   IF ::nLength > 0 .AND. ::nLength == ::nRead
      RETURN NIL
   ENDIF

   IF ! HB_ISNUMERIC( nLen ) .OR. nLen <= 0 .OR. ( ::nLength > 0 .AND. nLen > ::nLength - ::nRead )
      nLen := ::nLength - ::nRead
   ENDIF

   IF nLen <= 0
      // read till end of stream
      cStr1 := Space( RCV_BUF_SIZE )
      cStr0 := ""
      DO WHILE ( ::nLastRead := ::inetRecv( ::SocketCon, @cStr1, RCV_BUF_SIZE ) ) > 0
         ::nRead += ::nLastRead
         cStr0 += hb_BLeft( cStr1, ::nLastRead )
      ENDDO
      ::bEof := .T.
   ELSE
      // read an amount of data
      cStr0 := Space( nLen )

      IF ::lTLS .AND. ::lHasSSL
         /* Getting around implementing the hack used in non-SSL branch for now.
            IMO the proper fix would have been done to hb_inetRecvAll(). [vszakats] */
         ::nLastRead := ::inetRecvAll( ::SocketCon, @cStr0, nLen )
      ELSE
         // S.R. if len of file is less than RCV_BUF_SIZE hb_inetRecvAll return 0
         //      ::nLastRead := ::InetRecvAll( ::SocketCon, @cStr0, nLen )
         ::inetRecvAll( ::SocketCon, @cStr0, nLen )
         ::nLastRead := ::inetCount( ::SocketCon )
      ENDIF
      ::nRead += ::nLastRead

      IF ::nLastRead != nLen
         ::bEof := .T.
         cStr0 := hb_BLeft( cStr0, ::nLastRead )
#if 0
         RETURN NIL
#endif
      ENDIF

      IF ::nRead == ::nLength
         ::bEof := .T.
      ENDIF
   ENDIF

   RETURN cStr0

METHOD ReadToFile( /* @ */ cFile, nMode, nSize ) CLASS TIPClient

   LOCAL nFOut
   LOCAL cData
   LOCAL nSent := 0

   LOCAL lToMemory := hb_PIsByRef( 1 )

   hb_default( @nSize, 0 )

   IF lToMemory
      cFile := ""
   ENDIF

   IF HB_ISEVALITEM( ::exGauge )
      Eval( ::exGauge, nSent, nSize, Self )
   ENDIF

   ::nRead   := 0
   ::nStatus := 1

   DO WHILE ::inetErrorCode( ::SocketCon ) == 0 .AND. ! ::bEof
      IF ( cData := ::Read( RCV_BUF_SIZE ) ) == NIL
         IF nFOut != NIL
            FClose( nFOut )
         ENDIF
         RETURN ::inetErrorCode( ::SocketCon ) == 0
      ENDIF
      IF ! lToMemory .AND. nFOut == NIL
         IF ( nFOut := FCreate( cFile, nMode ) ) == F_ERROR
            ::nStatus := 0
            RETURN .F.
         ENDIF
      ENDIF

      IF lToMemory
         cFile += cData
      ELSEIF FWrite( nFOut, cData ) != hb_BLen( cData )
         FClose( nFOut )
         RETURN .F.
      ENDIF

      nSent += hb_BLen( cData )

      IF HB_ISEVALITEM( ::exGauge )
         Eval( ::exGauge, nSent, nSize, Self )
      ENDIF
   ENDDO

   IF nSent > 0
      ::Commit()
   ENDIF

   ::nStatus := 2
   IF nFOut != NIL
      FClose( nFOut )
   ENDIF
   IF ::inetErrorCode( ::SocketCon ) != 0
      RETURN .F.
   ENDIF

   RETURN .T.

METHOD WriteFromFile( cFile ) CLASS TIPClient

   LOCAL nFin
   LOCAL cData
   LOCAL nLen
   LOCAL nSize, nSent, nBufSize

   ::nWrite  := 0
   ::nStatus := 0
   IF ( nFin := FOpen( cFile ) ) == F_ERROR
      RETURN .F.
   ENDIF
   nSize := FSeek( nFin, 0, FS_END )
   FSeek( nFin, 0 )

   nBufSize := SND_BUF_SIZE

   // allow initialization of the gauge
   nSent := 0

   IF HB_ISEVALITEM( ::exGauge )
      Eval( ::exGauge, nSent, nSize, Self )
   ENDIF

   ::nStatus := 1
   cData := Space( nBufSize )
   DO WHILE ( nLen := FRead( nFin, @cData, nBufSize ) ) > 0
      IF ::Write( @cData, nLen ) != nLen
         FClose( nFin )
         RETURN .F.
      ENDIF
      nSent += nLen
      IF HB_ISEVALITEM( ::exGauge )
         Eval( ::exGauge, nSent, nSize, Self )
      ENDIF
   ENDDO

   // it may happen that the file has length 0
   IF nSent > 0
      ::Commit()
   ENDIF

   ::nStatus := 2
   FClose( nFin )

   RETURN .T.

METHOD Write( cData, nLen, lCommit ) CLASS TIPClient

   IF ! HB_ISNUMERIC( nLen ) .OR. nLen <= 0
      nLen := hb_BLen( cData )
   ENDIF

   ::nLastWrite := ::inetSendAll( ::SocketCon, cData, nLen )

   IF hb_defaultValue( lCommit, .F. )
      ::Commit()
   ENDIF

   ::nWrite += ::nLastWrite

   RETURN ::nLastWrite

METHOD inetSendAll( SocketCon, cData, nLen ) CLASS TIPClient

   LOCAL nRet

   IF ! HB_ISNUMERIC( nLen ) .OR. nLen <= 0
      nLen := hb_BLen( cData )
   ENDIF

   IF ::lTLS
      IF ::lHasSSL
#if defined( _SSL_DEBUG_TEMP )
         ? "SSL_write()", cData
#endif
         nRet := SSL_write( ::ssl, cData, nLen )
         ::nSSLError := iif( nRet < 0, nRet, 0 )
      ELSE
         nRet := 0
      ENDIF
   ELSE
      nRet := hb_inetSendAll( SocketCon, cData, nLen )
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, nlen, cData, nRet )
   ENDIF

   RETURN nRet

METHOD inetCount( SocketCon ) CLASS TIPClient

   LOCAL nRet := hb_inetCount( SocketCon )

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, nRet )
   ENDIF

   RETURN nRet

METHOD inetRecv( SocketCon, cStr1, len ) CLASS TIPClient

   LOCAL nRet

   IF ::lTLS
      IF ::lHasSSL
#if defined( _SSL_DEBUG_TEMP )
         ? "SSL_read()"
#endif
         nRet := SSL_read( ::ssl, @cStr1, len )
         ::nSSLError := iif( nRet < 0, nRet, 0 )
      ELSE
         nRet := 0
      ENDIF
   ELSE
      nRet := hb_inetRecv( SocketCon, @cStr1, len )
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, "", len, iif( nRet >= 0, cStr1, nRet ) )
   ENDIF

   RETURN nRet

METHOD inetRecvLine( SocketCon, nRet, size ) CLASS TIPClient

   LOCAL cRet

   IF ::lTLS
      IF ::lHasSSL
         nRet := hb_SSL_read_line( ::ssl, @cRet, size, ::nConnTimeout )
#if defined( _SSL_DEBUG_TEMP )
         ? "hb_SSL_read_line()", cRet
#endif
         IF nRet == 0 .OR. Empty( cRet )
            cRet := NIL
         ENDIF
         ::nSSLError := iif( nRet < 0, nRet, 0 )
      ELSE
         cRet := ""
         nRet := 0
      ENDIF
   ELSE
      cRet := hb_inetRecvLine( SocketCon, @nRet, size )
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, "", size, cRet )
   ENDIF

   RETURN cRet

METHOD inetRecvAll( SocketCon, cRet, size ) CLASS TIPClient

   LOCAL nRet

   IF ::lTLS
      IF ::lHasSSL
         nRet := hb_SSL_read_all( ::ssl, @cRet, size, ::nConnTimeout )
#if defined( _SSL_DEBUG_TEMP )
         ? "hb_SSL_read_all()", cRet
#endif
         IF nRet == 0 .OR. Empty( cRet )
            cRet := NIL
         ENDIF
         ::nSSLError := iif( nRet < 0, nRet, 0 )
      ELSE
         cRet := ""
         nRet := 0
      ENDIF
   ELSE
      nRet := hb_inetRecvAll( SocketCon, @cRet, size )
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, "", size, iif( nRet >= 0, cRet, nRet ) )
   ENDIF

   RETURN nRet

METHOD inetErrorCode( SocketCon ) CLASS TIPClient

   LOCAL nRet

   IF ::lTLS
      IF ::lHasSSL
         nRet := iif( ::nSSLError == 0, 0, SSL_get_error( ::ssl, ::nSSLError ) )
      ELSE
         nRet := 0
      ENDIF
   ELSE
      nRet := hb_inetErrorCode( SocketCon )
   ENDIF

   ::nLastError := nRet

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( SocketCon, nRet )
   ENDIF

   RETURN nRet

METHOD inetErrorDesc( SocketCon ) CLASS TIPClient

   hb_default( @SocketCon, ::SocketCon )

   IF ! Empty( SocketCon )
      IF ::lTLS
         IF ::lHasSSL .AND. ::nSSLError != 0
            RETURN ERR_error_string( SSL_get_error( ::ssl, ::nSSLError ) )
         ENDIF
      ELSE
         RETURN hb_inetErrorDesc( SocketCon )
      ENDIF
   ENDIF

   RETURN ""

/* BROKEN, should test number of parameters and act accordingly, see doc\inet.txt */
METHOD PROCEDURE inetConnect( cServer, nPort, SocketCon ) CLASS TIPClient

   hb_inetConnect( cServer, nPort, SocketCon )

   /* IMPORTANT: if internet connection is off and address is not
                 resolved and it is SSL compliant, then RTE must
                 be avoided [pritpal] */
   IF hb_inetStatus( SocketCon ) == -1
      RETURN
   ENDIF

   IF HB_ISNUMERIC( ::nDefaultSndBuffSize )
      ::InetSndBufSize( SocketCon, ::nDefaultSndBuffSize )
   ENDIF
   IF HB_ISNUMERIC( ::nDefaultRcvBuffSize )
      ::InetRcvBufSize( SocketCon, ::nDefaultRcvBuffSize )
   ENDIF

   IF ::lTLS .AND. ::lHasSSL
      SSL_set_mode( ::ssl, HB_SSL_MODE_AUTO_RETRY )
      SSL_set_fd( ::ssl, hb_inetFD( SocketCon ) )
      SSL_connect( ::ssl )
      /* TODO: Add error handling */
   ENDIF

   IF HB_ISEVALITEM( ::bTrace )
      ::Log( cServer, nPort, SocketCon )
   ENDIF

   RETURN

/* Methods to manage buffers */
METHOD InetRcvBufSize( SocketCon, nSizeBuff ) CLASS TIPClient

   IF HB_ISNUMERIC( nSizeBuff ) .AND. nSizeBuff > 0
      hb_inetSetRcvBufSize( SocketCon, nSizeBuff )
   ENDIF

   RETURN hb_inetGetRcvBufSize( SocketCon )

METHOD InetSndBufSize( SocketCon, nSizeBuff ) CLASS TIPClient

   IF HB_ISNUMERIC( nSizeBuff ) .AND. nSizeBuff > 0
      hb_inetSetSndBufSize( SocketCon, nSizeBuff )
   ENDIF

   RETURN hb_inetGetSndBufSize( SocketCon )

METHOD InetTimeOut( SocketCon, nConnTimeout ) CLASS TIPClient

   IF HB_ISNUMERIC( nConnTimeout )
      ::nConnTimeout := nConnTimeout
   ENDIF
   IF HB_ISNUMERIC( ::nConnTimeout )
      RETURN hb_inetTimeout( SocketCon, ::nConnTimeout )
   ENDIF

   RETURN NIL

/* Called from another method with list of parameters and, as last parameter, return code
   of function being logged.
   Example, I want to log MyFunc( a, b, c ) which returns m,
            ::Log( a, b, c, m ) */
METHOD Log( ... ) CLASS TIPClient

   LOCAL xVar
   LOCAL cMsg

   IF HB_ISEVALITEM( ::bTrace )

      cMsg := DToS( Date() ) + "-" + Time() + Space( 2 ) + ;
         SubStr( ProcName( 1 ), RAt( ":", ProcName( 1 ) ) ) + ;
         "( "

      FOR EACH xVar IN hb_AParams()

         // Preserves CRLF on result
         IF xVar:__enumIsLast()
            cMsg += hb_CStr( xVar )
         ELSE
            cMsg += hb_StrReplace( AllTrim( hb_CStr( xVar ) ), Chr( 13 ) + Chr( 10 ), { "<cr>", "<lf>" } )
         ENDIF

         DO CASE
         CASE xVar:__enumIndex() < Len( xVar:__enumBase() ) - 1
            cMsg += ", "
         CASE xVar:__enumIndex() == Len( xVar:__enumBase() ) - 1
            cMsg += " )" + hb_eol() + ">> "
         CASE xVar:__enumIsLast()
            cMsg += " <<" + hb_eol() + hb_eol()
         ENDCASE
      NEXT

      Eval( ::bTrace, cMsg )
   ENDIF

   RETURN Self

METHOD SetProxy( cProxyHost, nProxyPort, cProxyUser, cProxyPassword ) CLASS TIPClient

   IF HB_ISOBJECT( cProxyHost ) .AND. cProxyHost:className() == "TURL"
      ::cProxyHost     := cProxyHost:cServer
      ::nProxyPort     := cProxyHost:nPort
      ::cProxyUser     := cProxyHost:cUserid
      ::cProxyPassword := cProxyHost:cPassword
   ELSE
      ::cProxyHost     := hb_defaultValue( cProxyHost, "" )
      ::nProxyPort     := hb_defaultValue( nProxyPort, 0 )
      ::cProxyUser     := hb_defaultValue( cProxyUser, "" )
      ::cProxyPassword := hb_defaultValue( cProxyPassword, "" )
   ENDIF

   RETURN Self

FUNCTION tip_SSL()
   RETURN hb_IsFunction( "__HBEXTERN__HBSSL__" )