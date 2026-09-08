<?xml version="1.0" encoding="UTF-8"?>
<!--
  The bare identity-transform starter. Drop in, then add your overrides below.
  Every enrichment XSL in this codebase begins from this file.
-->
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:exf="http://sap.com/it/"
                xmlns:xs="http://www.w3.org/2001/XMLSchema">

  <xsl:output method="xml" indent="yes"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <!-- Your overrides go below. Examples:

       <xsl:template match="DebugInfo"/>                            (drop)
       <xsl:template match="OldName"><NewName>...</NewName></...>   (rename)
       <xsl:template match="X/Y">...add child...</...>              (enrich)
  -->

</xsl:stylesheet>
